import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';

void main() {
  const folder = '/notes';
  const password = 'hunter2';

  late _InMemoryFolderLockRepository repository;
  late _EchoHasher hasher;
  late FolderLockService service;

  setUp(() {
    repository = _InMemoryFolderLockRepository();
    hasher = _EchoHasher();
    service = FolderLockService(repository: repository, hasher: hasher);
  });

  tearDown(() => service.dispose());

  group('FolderLockService.lock', () {
    test('locks a folder with an acceptable password', () async {
      final result = await service.lock(folder, password);

      expect(result, isA<FolderLocked>());
      final lock = repository.locks[folder];
      expect(lock, isNotNull);
      expect(lock!.iterations, hasher.iterations);
      expect(lock.salt, hasher.salt);
      expect(
        hasher.matches(
          password,
          salt: lock.salt,
          iterations: lock.iterations,
          expectedHash: lock.hash,
        ),
        isTrue,
      );
    });

    test('an empty password is refused with the PRD copy (FR-41)', () async {
      final result = await service.lock(folder, '');

      expect(result, isA<LockPasswordRejected>());
      expect((result as LockPasswordRejected).message, 'Enter a password.');
      expect(repository.locks, isEmpty);
    });

    test('a password shorter than four characters is refused (PW-2)', () async {
      final result = await service.lock(folder, 'abc');

      expect(result, isA<LockPasswordRejected>());
      expect(
        (result as LockPasswordRejected).message,
        'Use at least 4 characters.',
      );
      expect(repository.locks, isEmpty);
    });

    test('four characters are enough (PW-2)', () async {
      expect(await service.lock(folder, 'abcd'), isA<FolderLocked>());
    });

    test('each emoji counts as one character (PW-3)', () async {
      expect(
        await service.lock('/emoji-short', '🔒🔒'),
        isA<LockPasswordRejected>(),
      );
      expect(
        await service.lock('/emoji-enough', '🔒🔒🔒🔒'),
        isA<FolderLocked>(),
      );
    });

    test('nothing is trimmed or case-folded (PW-1)', () async {
      await service.lock(folder, 'Ab c ');

      final lock = repository.locks[folder]!;
      expect(
        hasher.matches(
          'Ab c ',
          salt: lock.salt,
          iterations: lock.iterations,
          expectedHash: lock.hash,
        ),
        isTrue,
      );
      expect(
        hasher.matches(
          'ab c',
          salt: lock.salt,
          iterations: lock.iterations,
          expectedHash: lock.hash,
        ),
        isFalse,
      );
    });

    test('never stores the password itself (NFR-5)', () async {
      await service.lock(folder, password);

      expect(repository.locks[folder]!.encode().contains(password), isFalse);
    });

    test('a folder that is already locked keeps its first password', () async {
      await service.lock(folder, 'first');
      final firstLock = repository.locks[folder]!;

      final result = await service.lock(folder, 'second');

      expect(result, isA<FolderAlreadyLocked>());
      expect(repository.writes, 1);
      expect(identical(repository.locks[folder], firstLock), isTrue);
      expect(
        hasher.matches(
          'second',
          salt: firstLock.salt,
          iterations: firstLock.iterations,
          expectedHash: firstLock.hash,
        ),
        isFalse,
      );
    });

    test(
      'a failed write reports failure and leaves the folder unlocked',
      () async {
        repository.failWrites = true;

        final result = await service.lock(folder, password);

        expect(result, isA<LockSaveFailed>());
        expect(repository.locks, isEmpty);
      },
    );

    test('listeners hear only about locks that appeared', () async {
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.lock(folder, '');
      expect(notifications, 0, reason: 'an empty password changes nothing');

      await service.lock(folder, password);
      expect(notifications, 1);

      await service.lock(folder, password);
      expect(notifications, 1, reason: 'an existing lock is not news');

      repository.failWrites = true;
      await service.lock('/other', password);
      expect(notifications, 1, reason: 'a failed lock did not appear');
    });
  });

  group('FolderLockService.unlock', () {
    setUp(() async {
      await service.lock('/notes', 'hunter2');
    });

    test('the right password opens the folder and what is inside it', () async {
      final result = await service.unlock('/notes', 'hunter2');

      expect(result, isA<FolderUnlocked>());
      expect((result as FolderUnlocked).folder, '/notes');
      expect(await service.isOpen('/notes'), isTrue);
      expect(await service.isOpen('/notes/diary.sbn2'), isTrue);
    });

    test('a wrong password leaves the folder closed (FR-12, FR-19)', () async {
      final result = await service.unlock('/notes', 'wrong');

      expect(result, isA<UnlockRefused>());
      expect((result as UnlockRefused).message, 'Wrong password.');
      expect(await service.isOpen('/notes'), isFalse);
      expect(await service.isOpen('/notes/diary.sbn2'), isFalse);
    });

    test(
      'a note unlocks its folder, not just the note (FR-13, FR-16)',
      () async {
        final result = await service.unlock('/notes/diary.sbn2', 'hunter2');

        expect((result as FolderUnlocked).folder, '/notes');
        expect(await service.isOpen('/notes'), isTrue);
      },
    );

    test('a corrupt record refuses every password (NFR-8)', () async {
      repository.corrupt.add('/notes');

      final result = await service.unlock('/notes', 'hunter2');

      expect(result, isA<UnlockRefused>());
      expect(await service.isOpen('/notes'), isFalse);
    });

    test('nothing locked means there is nothing to unlock', () async {
      expect(
        await service.unlock('/unlocked', 'anything'),
        isA<NothingToUnlock>(),
      );
      expect(await service.isOpen('/unlocked'), isTrue);
    });

    test(
      'unlocking a nested folder leaves the parent asking (FR-15)',
      () async {
        await service.lock('/notes/private', 'inner');

        expect(
          await service.unlock('/notes/private', 'hunter2'),
          isA<UnlockRefused>(),
          reason: 'the inner folder wants its own password',
        );

        await service.unlock('/notes/private', 'inner');

        expect(await service.isOpen('/notes/private'), isTrue);
        expect(
          await service.isOpen('/notes/other.sbn2'),
          isFalse,
          reason: 'unlocking a child must not unlock the parent',
        );

        await service.unlock('/notes', 'hunter2');
        expect(
          await service.isOpen('/notes/private'),
          isTrue,
          reason: 'the inner folder stays open once unlocked itself',
        );
      },
    );

    test('relockAll closes everything and tells listeners (FR-28)', () async {
      await service.unlock('/notes', 'hunter2');
      var notifications = 0;
      service.addListener(() => notifications++);

      service.relockAll();

      expect(notifications, 1);
      expect(await service.isOpen('/notes'), isFalse);
    });

    test('relockAll with nothing open stays quiet', () {
      var notifications = 0;
      service.addListener(() => notifications++);

      service.relockAll();

      expect(notifications, 0);
    });

    test('an unlock whose record disappeared is forgotten', () async {
      await service.unlock('/notes', 'hunter2');

      // The folder was deleted outside the app.
      await repository.delete('/notes');
      expect(await service.isOpen('/notes/diary.sbn2'), isTrue);

      // Locked again, the stale session entry must not open it.
      await service.lock('/notes', 'new password');
      expect(await service.isOpen('/notes'), isFalse);
    });

    test(
      'Windows separators and trailing slashes name the same folder',
      () async {
        await service.lock(r'\notes\', 'hunter2');

        expect(
          await service.unlock('/notes/', 'hunter2'),
          isA<FolderUnlocked>(),
        );
        expect(await service.isOpen(r'\notes'), isTrue);
      },
    );
  });

  group('Nested locks (FR-15, SABER-14)', () {
    test('the outer password does not open the inner lock', () async {
      await service.lock('/notes', 'outer');
      await service.lock('/notes/private', 'inner');

      expect(await service.unlock('/notes', 'outer'), isA<FolderUnlocked>());
      expect(await service.isOpen('/notes'), isTrue);
      expect(await service.isOpen('/notes/private'), isFalse);
      expect(await service.isOpen('/notes/private/diary.sbn2'), isFalse);

      expect(
        await service.unlock('/notes/private', 'inner'),
        isA<FolderUnlocked>(),
      );
      expect(await service.isOpen('/notes/private/diary.sbn2'), isTrue);
    });

    test('three levels deep behave the same', () async {
      await service.lock('/a', 'one-up');
      await service.lock('/a/b', 'two-up');
      await service.lock('/a/b/c', 'three-up');

      await service.unlock('/a', 'one-up');
      expect(await service.isOpen('/a'), isTrue);
      expect(await service.isOpen('/a/b'), isFalse);
      expect(await service.isOpen('/a/b/c'), isFalse);

      await service.unlock('/a/b', 'two-up');
      expect(await service.isOpen('/a/b'), isTrue);
      expect(await service.isOpen('/a/b/c'), isFalse);

      await service.unlock('/a/b/c', 'three-up');
      expect(await service.isOpen('/a/b/c/note.sbn2'), isTrue);
    });

    test(
      'renaming a parent keeps an unlocked child open at its new path',
      () async {
        await service.lock('/notes', 'outer');
        await service.lock('/notes/private', 'inner');
        await service.unlock('/notes', 'outer');
        await service.unlock('/notes/private', 'inner');

        // FileManager moves the directory; its records move with it.
        repository.locks['/team'] = repository.locks.remove('/notes')!;
        repository.locks['/team/private'] = repository.locks.remove(
          '/notes/private',
        )!;

        service.folderMoved(from: '/notes', to: '/team');

        expect(
          await service.isOpen('/team/private'),
          isTrue,
          reason: 'the child keeps the session it was given',
        );
        expect(await service.isLocked('/team'), isTrue);
        expect(
          await service.isOpen('/team'),
          isFalse,
          reason: 'the renamed folder itself asks again',
        );
      },
    );

    test('renaming /A leaves the session of /AB alone', () async {
      await service.lock('/A', 'alpha');
      await service.lock('/AB', 'bravo');
      await service.unlock('/A', 'alpha');
      await service.unlock('/AB', 'bravo');

      repository.locks['/C'] = repository.locks.remove('/A')!;
      service.folderMoved(from: '/A', to: '/C');

      expect(
        await service.isOpen('/AB'),
        isTrue,
        reason: '/AB is not inside /A, so its entry must survive untouched',
      );
      expect(await service.isOpen('/C'), isFalse);
    });

    test('a move with nothing open stays quiet', () {
      var notifications = 0;
      service.addListener(() => notifications++);

      service.folderMoved(from: '/notes', to: '/team');

      expect(notifications, 0);
    });

    test('a folder moved under a lock is decided by its new parent', () async {
      await service.lock('/open', 'openpw');
      await service.lock('/locked', 'secret');
      await service.unlock('/open', 'openpw');
      expect(await service.isOpen('/open/child'), isTrue);

      service.folderMoved(from: '/open/child', to: '/locked/child');

      expect(
        await service.isOpen('/locked/child'),
        isFalse,
        reason: 'the destination folder is locked, so it is the nearest lock',
      );

      await service.unlock('/locked', 'secret');
      expect(await service.isOpen('/locked/child'), isTrue);
    });
  });

  group('FolderLockService.remove', () {
    setUp(() async {
      await service.lock('/notes', 'hunter2');
    });

    test('the right password removes the lock (FR-5)', () async {
      final result = await service.remove('/notes', 'hunter2');

      expect(result, isA<LockRemoved>());
      expect(repository.locks, isEmpty);
      expect(await service.isLocked('/notes'), isFalse);
      expect(await service.isOpen('/notes'), isTrue);
    });

    test('removing tells listeners so badges can go (FR-6)', () async {
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.remove('/notes', 'hunter2');

      expect(notifications, 1);
    });

    test('a wrong password leaves the record untouched', () async {
      final result = await service.remove('/notes', 'wrong');

      expect(result, isA<RemoveWrongPassword>());
      expect((result as RemoveWrongPassword).message, 'Wrong password.');
      expect(repository.locks.containsKey('/notes'), isTrue);
      expect(await service.unlock('/notes', 'hunter2'), isA<FolderUnlocked>());
    });

    test('removing twice is a no-op', () async {
      expect(await service.remove('/notes', 'hunter2'), isA<LockRemoved>());

      expect(await service.remove('/notes', 'hunter2'), isA<RemoveNotLocked>());
    });

    test('a folder that was never locked has nothing to remove', () async {
      expect(await service.remove('/other', 'hunter2'), isA<RemoveNotLocked>());
    });

    test('a corrupt record cannot be removed (NFR-8)', () async {
      repository.corrupt.add('/notes');

      expect(
        await service.remove('/notes', 'hunter2'),
        isA<RemoveCorruptLock>(),
      );
      expect(await service.isLocked('/notes'), isTrue);
    });

    test('a failed delete keeps the lock (HLD §12)', () async {
      repository.failDeletes = true;

      expect(await service.remove('/notes', 'hunter2'), isA<RemoveFailed>());
      expect(await service.isLocked('/notes'), isTrue);
    });

    test('removing from a note removes its folder lock', () async {
      expect(
        await service.remove('/notes/entry.sbn2', 'hunter2'),
        isA<LockRemoved>(),
      );
      expect(await service.isLocked('/notes'), isFalse);
    });
  });
}

/// A hasher that maps a password to recognisable bytes, so the service tests
/// stay about rules and outcomes rather than about PBKDF2.
final class _EchoHasher implements PasswordHasher {
  static const _salt = [1, 2, 3, 4];

  final salt = Uint8List.fromList(_salt);

  @override
  int get iterations => 2;

  @override
  Uint8List createSalt() => Uint8List.fromList(_salt);

  @override
  Uint8List derive(
    String password, {
    required Uint8List salt,
    required int iterations,
  }) => Uint8List.fromList(
    utf8.encode('$iterations:$password:${base64Encode(salt)}'),
  );

  @override
  bool matches(
    String password, {
    required Uint8List salt,
    required int iterations,
    required Uint8List expectedHash,
  }) {
    final actual = derive(password, salt: salt, iterations: iterations);
    if (actual.length != expectedHash.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expectedHash[i]) return false;
    }
    return true;
  }
}

final class _InMemoryFolderLockRepository implements FolderLockRepository {
  final locks = <String, FolderLock>{};
  final corrupt = <String>{};
  var failWrites = false;
  var failDeletes = false;
  var writes = 0;

  @override
  Future<FolderLockRead?> read(String folderPath) async {
    if (corrupt.contains(folderPath)) {
      return const FolderLockCorrupt('unreadable record');
    }
    final lock = locks[folderPath];
    return lock == null ? null : FolderLockFound(lock);
  }

  @override
  Future<FolderLockWriteResult> write(
    String folderPath,
    FolderLock lock,
  ) async {
    if (failWrites) return const FolderLockWriteFailed('disk full');
    writes++;
    locks[folderPath] = lock;
    return const FolderLockWritten();
  }

  @override
  Future<bool> delete(String folderPath) async {
    if (failDeletes) return false;
    locks.remove(folderPath);
    return true;
  }

  @override
  Future<bool> exists(String folderPath) async => locks.containsKey(folderPath);
}
