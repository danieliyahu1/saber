import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/pbkdf2_password_hasher.dart';

void main() {
  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  final hash = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  final lock = FolderLock(salt: salt, iterations: 100000, hash: hash);

  FolderLock? read(String contents) {
    final result = FolderLock.read(contents);
    return result is FolderLockFound ? result.lock : null;
  }

  group('FolderLock', () {
    test('survives a trip through JSON unchanged', () {
      expect(read(lock.encode()), lock);
    });

    test('stores the salt and cost a later check would need', () {
      expect(lock.toJson(), {
        'v': FolderLock.currentVersion,
        'salt': base64Encode(salt),
        'iterations': 100000,
        'hash': base64Encode(hash),
      });
    });

    test('never contains the password (NFR-5)', () {
      const password = 'correct horse battery staple';
      final hasher = Pbkdf2PasswordHasher();
      final realSalt = hasher.createSalt();
      final realLock = FolderLock(
        salt: realSalt,
        iterations: 1000,
        hash: hasher.derive(password, salt: realSalt, iterations: 1000),
      );

      expect(realLock.encode().contains(password), isFalse);
    });

    test('accepts an empty hash: emptiness is not a codec question', () {
      final empty = FolderLock(salt: salt, iterations: 1, hash: Uint8List(0));

      expect(read(empty.encode()), empty);
    });

    test('ignores fields a newer build might add', () {
      final json = lock.toJson()..['note'] = 'from the future';

      expect(read(jsonEncode(json)), lock);
    });

    test('compares by value, not identity', () {
      final copy = FolderLock(
        salt: Uint8List.fromList(salt),
        iterations: 100000,
        hash: Uint8List.fromList(hash),
      );

      expect(copy, lock);
      expect(copy.hashCode, lock.hashCode);
    });
  });

  group('a corrupt record is reported, never thrown (NFR-8)', () {
    final cases = <String, String>{
      'empty file': '',
      'not JSON': 'not a lock',
      'JSON that is not an object': '[1, 2, 3]',
      'a missing version': '{"salt":"c2FsdA==","iterations":1,"hash":""}',
      'a version that is not a number':
          '{"v":"1","salt":"c2FsdA==","iterations":1,"hash":""}',
      'a version this build cannot read':
          '{"v":2,"salt":"c2FsdA==","iterations":1,"hash":""}',
      'a missing salt': '{"v":1,"iterations":1,"hash":""}',
      'a salt that is not base64':
          '{"v":1,"salt":"!!","iterations":1,"hash":""}',
      'a missing iteration count': '{"v":1,"salt":"c2FsdA==","hash":""}',
      'an iteration count below one':
          '{"v":1,"salt":"c2FsdA==","iterations":0,"hash":""}',
      'a missing hash': '{"v":1,"salt":"c2FsdA==","iterations":1}',
      'a hash that is not base64':
          '{"v":1,"salt":"c2FsdA==","iterations":1,"hash":"??"}',
    };

    for (final MapEntry(key: description, value: contents) in cases.entries) {
      test(description, () {
        expect(FolderLock.read(contents), isA<FolderLockCorrupt>());
      });
    }
  });
}
