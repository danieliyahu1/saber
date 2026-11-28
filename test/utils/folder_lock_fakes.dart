import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';

/// In-memory lock records, so widget tests do not need a disk.
class MemoryFolderLockRepository implements FolderLockRepository {
  final locks = <String, FolderLock>{};
  final corrupt = <String>{};

  /// When set, [exists] waits for it, holding a check in flight.
  Completer<void>? gate;

  var existsCalls = 0;
  var reads = 0;
  var failWrites = false;
  var failDeletes = false;

  @override
  Future<bool> exists(String folderPath) async {
    existsCalls++;
    if (gate case final pending?) await pending.future;
    return locks.containsKey(folderPath);
  }

  @override
  Future<FolderLockRead?> read(String folderPath) async {
    reads++;
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
    locks[folderPath] = lock;
    return const FolderLockWritten();
  }

  @override
  Future<bool> delete(String folderPath) async {
    if (failDeletes) return false;
    locks.remove(folderPath);
    return true;
  }
}

/// Maps a password to recognisable bytes; PBKDF2 has its own tests.
class EchoPasswordHasher implements PasswordHasher {
  static const _salt = [1, 2, 3, 4];

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

/// A lock record that accepts [password].
FolderLock lockAccepting(String password) {
  final hasher = EchoPasswordHasher();
  final salt = hasher.createSalt();
  return FolderLock(
    salt: salt,
    iterations: hasher.iterations,
    hash: hasher.derive(password, salt: salt, iterations: hasher.iterations),
  );
}
