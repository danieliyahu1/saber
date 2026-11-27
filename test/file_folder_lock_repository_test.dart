import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/file_folder_lock_repository.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/prefs.dart';

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
}
