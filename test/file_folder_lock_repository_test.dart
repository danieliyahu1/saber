import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/file_folder_lock_repository.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMockPathProvider();
  FlavorConfig.setup();

  const repository = FileFolderLockRepository();
  const folder = '/folder_lock_repository_test';
  const recordPath = '$folder/${FileFolderLockRepository.fileName}';

  final lock = FolderLock(
    salt: Uint8List.fromList(List.generate(16, (i) => i)),
    iterations: 1000,
    hash: Uint8List.fromList(List.generate(32, (i) => i)),
  );

  setUpAll(() async {
    await FileManager.init();
  });

  setUp(() async {
    await FileManager.createFolder(folder);
    stows.recentFiles.value = [];
  });

  tearDown(() async {
    await FileManager.deleteDirectory(folder);
    stows.recentFiles.value = [];
  });

  group('FileFolderLockRepository', () {
    test('a written record reads back unchanged', () async {
      expect(await repository.write(folder, lock), isA<FolderLockWritten>());

      final read = await repository.read(folder);

      expect(read, isA<FolderLockFound>());
      expect((read! as FolderLockFound).lock, lock);
    });

    test('the record is a dotfile beside the notes', () async {
      await repository.write(folder, lock);

      expect(FileManager.doesFileExist(recordPath), isTrue);
    });

    test('writing a record does not put it in recent notes (FR-20)', () async {
      const notePath = '$folder/note.sbn2';
      await FileManager.writeFile(notePath, [1], awaitWrite: true);

      await repository.write(folder, lock);

      expect(stows.recentFiles.value, [notePath]);
    });

    test('a trailing slash names the same folder', () async {
      await repository.write(folder, lock);

      expect(await repository.exists('$folder/'), isTrue);
      expect(await repository.read('$folder/'), isA<FolderLockFound>());
    });

    test('a folder with no record is not locked', () async {
      expect(await repository.read(folder), isNull);
      expect(await repository.exists(folder), isFalse);
    });

    test('exists tracks write and delete', () async {
      await repository.write(folder, lock);
      expect(await repository.exists(folder), isTrue);

      expect(await repository.delete(folder), isTrue);
      expect(await repository.exists(folder), isFalse);
    });

    test('deleting the record unlocks the folder', () async {
      await repository.write(folder, lock);

      await repository.delete(folder);

      expect(await repository.read(folder), isNull);
      expect(FileManager.doesFileExist(recordPath), isFalse);
    });

    test('deleting a record that is already gone is a no-op', () async {
      expect(await repository.delete(folder), isTrue);
    });

    test('an unreadable record is reported, never thrown (NFR-8)', () async {
      await FileManager.getFile(recordPath).writeAsString('not a lock');

      expect(await repository.read(folder), isA<FolderLockCorrupt>());
    });

    test('bytes that are not UTF-8 are corrupt, not an exception', () async {
      await FileManager.getFile(recordPath).writeAsBytes([0xff, 0xfe, 0xfd]);

      expect(await repository.read(folder), isA<FolderLockCorrupt>());
    });

    test('an empty record is corrupt, not unlocked (NFR-8)', () async {
      await FileManager.getFile(recordPath).writeAsBytes([]);

      expect(await repository.read(folder), isA<FolderLockCorrupt>());
    });

    test(
      'a write to a folder that does not exist fails and creates nothing',
      () async {
        const ghost = '/folder_lock_repository_ghost';

        expect(
          await repository.write(ghost, lock),
          isA<FolderLockWriteFailed>(),
        );
        expect(
          Directory('${FileManager.documentsDirectory}$ghost').existsSync(),
          isFalse,
        );
      },
    );

    test('a write that cannot land reports failure', () async {
      // A directory squatting on the record's path makes the write fail the
      // way a full or read-only disk would.
      await Directory('${FileManager.documentsDirectory}$recordPath').create();

      expect(
        await repository.write(folder, lock),
        isA<FolderLockWriteFailed>(),
      );
    });
  });

  group('The lock follows a rename (FR-25, SABER-30)', () {
    const original = '/folder_lock_rename_source';
    const target = '/folder_lock_rename_target';
    const taken = '/folder_lock_rename_taken';

    late FolderLockService service;

    setUp(() async {
      await FileManager.createFolder(original);
      await FileManager.writeFile(
        '$original/entry.sbn2',
        [1],
        awaitWrite: true,
      );
      service = FolderLockService(
        repository: repository,
        hasher: EchoPasswordHasher(),
      );
    });

    tearDown(() async {
      service.dispose();
      await FileManager.deleteDirectory(original);
      await FileManager.deleteDirectory(target);
      await FileManager.deleteDirectory(taken);
      await FileManager.deleteDirectory('$taken (2)');
    });

    test('the record is at the new path and gone from the old one', () async {
      expect(await service.lock(original, 'hunter2'), isA<FolderLocked>());

      final newPath = await FileManager.renameDirectory(
        original,
        'folder_lock_rename_target',
      );

      expect(newPath, target);
      expect(await repository.exists(target), isTrue);
      expect(await repository.exists(original), isFalse);
      expect(await service.isLocked(target), isTrue);
      expect(await service.unlock(target, 'hunter2'), isA<FolderUnlocked>());
    });

    test('a name that is already taken is suffixed and keeps the lock', () async {
      await FileManager.createFolder(taken);
      expect(await service.lock(original, 'hunter2'), isA<FolderLocked>());

      final newPath = await FileManager.renameDirectory(
        original,
        'folder_lock_rename_taken',
      );

      expect(newPath, '$taken (2)');
      expect(await repository.exists('$taken (2)'), isTrue);
      expect(await service.isLocked('$taken (2)'), isTrue);
    });

    test('a folder renamed while unlocked asks again afterwards', () async {
      await service.lock(original, 'hunter2');
      await service.unlock(original, 'hunter2');
      expect(await service.isOpen(original), isTrue);

      final newPath = await FileManager.renameDirectory(
        original,
        'folder_lock_rename_target',
      );
      service.folderMoved(from: original, to: newPath);

      expect(
        await service.isOpen(newPath),
        isFalse,
        reason: 'a rename is a new path, so the folder asks again',
      );
    });
  });
}
