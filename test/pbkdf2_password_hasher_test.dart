import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';
import 'package:saber/data/folder_lock/pbkdf2_password_hasher.dart';

void main() {
  final PasswordHasher hasher = Pbkdf2PasswordHasher();

  /// A salt is just bytes; using `'salt'` keeps the published test vectors
  /// recognisable.
  final salt = _bytes('salt');

  group('Pbkdf2PasswordHasher', () {
    test('derives the published PBKDF2-HMAC-SHA256 vectors', () {
      // RFC 7914 §11 / the common PBKDF2-SHA256 vectors, computed
      // independently with Python's hashlib.pbkdf2_hmac.
      const vectors = {
        1: '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        2: 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        4096:
            'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      };

      for (final MapEntry(key: iterations, value: expected) in vectors.entries) {
        final actual = hasher.derive(
          'password',
          salt: salt,
          iterations: iterations,
        );
        expect(
          _toHex(actual),
          expected,
          reason: '$iterations iteration(s)',
        );
      }
    });

    test('derives 32 bytes, as the lock record expects', () {
      final hash = hasher.derive('password', salt: salt, iterations: 1);
      expect(hash, hasLength(Pbkdf2PasswordHasher.hashLength));
      expect(Pbkdf2PasswordHasher.hashLength, 32);
    });

    test('is deterministic for the same password, salt and cost', () {
      final first = hasher.derive('correct horse', salt: salt, iterations: 2);
      final second = hasher.derive('correct horse', salt: salt, iterations: 2);
      expect(first, second);
    });

    test('changing the password, salt or cost changes the hash', () {
      final base = hasher.derive('password', salt: salt, iterations: 2);
      final variations = {
        'password': hasher.derive('Password', salt: salt, iterations: 2),
        'salt': hasher.derive(
          'password',
          salt: _bytes('pepper'),
          iterations: 2,
        ),
        'iterations': hasher.derive('password', salt: salt, iterations: 3),
      };

      for (final MapEntry(key: change, value: hash) in variations.entries) {
        expect(hash, isNot(base), reason: 'changing the $change must matter');
      }
    });

    test('matches the password it was derived from', () {
      final hash = hasher.derive('hunter2!', salt: salt, iterations: 2);
      expect(
        hasher.matches(
          'hunter2!',
          salt: salt,
          iterations: 2,
          expectedHash: hash,
        ),
        isTrue,
      );
    });

    test('rejects a hash that differs in any single byte', () {
      final hash = hasher.derive('password', salt: salt, iterations: 1);
      final positions = [0, hash.length ~/ 2, hash.length - 1];

      for (final position in positions) {
        final tampered = Uint8List.fromList(hash);
        tampered[position] ^= 0x01;
        expect(
          hasher.matches(
            'password',
            salt: salt,
            iterations: 1,
            expectedHash: tampered,
          ),
          isFalse,
          reason: 'a difference at byte $position must be noticed',
        );
      }
    });

    test('rejects a stored hash of a different length without throwing', () {
      final hash = hasher.derive('password', salt: salt, iterations: 1);
      final candidates = <Uint8List>[
        Uint8List(0),
        hash.sublist(0, hash.length - 1),
        Uint8List.fromList([...hash, 0]),
      ];

      for (final candidate in candidates) {
        expect(
          () => hasher.matches(
            'password',
            salt: salt,
            iterations: 1,
            expectedHash: candidate,
          ),
          returnsNormally,
        );
        expect(
          hasher.matches(
            'password',
            salt: salt,
            iterations: 1,
            expectedHash: candidate,
          ),
          isFalse,
          reason: 'a ${candidate.length}-byte hash cannot be valid',
        );
      }
    });

    test('rejects an iteration count below one', () {
      expect(
        () => hasher.derive('password', salt: salt, iterations: 0),
        throwsArgumentError,
      );
    });
  });

  group('PRD password rules (PW-1, PW-3, PW-4)', () {
    test('compares exactly what was typed: case and spaces matter', () {
      const password = 'Open Sesame';
      final hash = hasher.derive(password, salt: salt, iterations: 1);

      const nearMisses = [
        'open sesame', // different case
        'Open Sesame ', // trailing space
        ' Open Sesame', // leading space
        'Open  Sesame', // extra space
        'OpenSesame', // no space
      ];

      for (final nearMiss in nearMisses) {
        expect(
          hasher.matches(
            nearMiss,
            salt: salt,
            iterations: 1,
            expectedHash: hash,
          ),
          isFalse,
          reason: '"$nearMiss" is not the password',
        );
      }
    });

    test('does not normalise unicode', () {
      const composed = 'café'; // U+00E9
      const decomposed = 'cafe\u0301'; // e + combining acute
      expect(composed, isNot(decomposed));

      final hash = hasher.derive(composed, salt: salt, iterations: 1);
      expect(
        hasher.matches(
          decomposed,
          salt: salt,
          iterations: 1,
          expectedHash: hash,
        ),
        isFalse,
      );
    });

    test('counts every character, including emoji and spaces', () {
      const passwords = [
        '🔒 lock',
        '🔒  lock',
        '🔒lock',
        'a b',
        'ab',
      ];

      final hashes = {
        for (final password in passwords)
          password: _toHex(
            hasher.derive(password, salt: salt, iterations: 1),
          ),
      };

      expect(hashes.values.toSet(), hasLength(passwords.length));
      for (final MapEntry(key: password, value: hexHash) in hashes.entries) {
        expect(
          hasher.matches(
            password,
            salt: salt,
            iterations: 1,
            expectedHash: _bytesFromHex(hexHash),
          ),
          isTrue,
          reason: '"$password" must unlock itself',
        );
      }
    });

    test('hashes an empty password without complaint', () {
      // Emptiness is a dialog validation concern (PW-2), not a hashing one.
      final hash = hasher.derive('', salt: salt, iterations: 1);
      expect(hash, hasLength(Pbkdf2PasswordHasher.hashLength));
      expect(
        hasher.matches('', salt: salt, iterations: 1, expectedHash: hash),
        isTrue,
      );
      expect(
        hasher.matches(' ', salt: salt, iterations: 1, expectedHash: hash),
        isFalse,
      );
    });

    test('has no maximum length (PW-4)', () {
      final longPassword = 'a' * 10000;

      final hash = hasher.derive(longPassword, salt: salt, iterations: 1);
      expect(hash, hasLength(Pbkdf2PasswordHasher.hashLength));
      expect(
        hasher.matches(
          longPassword,
          salt: salt,
          iterations: 1,
          expectedHash: hash,
        ),
        isTrue,
      );
      expect(
        hasher.matches(
          longPassword.substring(1),
          salt: salt,
          iterations: 1,
          expectedHash: hash,
        ),
        isFalse,
      );
    });
  });

  group('Salt and cost', () {
    test('creates 16 random bytes', () {
      expect(Pbkdf2PasswordHasher.saltLength, 16);

      final first = hasher.createSalt();
      final second = hasher.createSalt();
      expect(first, hasLength(16));
      expect(second, hasLength(16));
      expect(_toHex(first), isNot(_toHex(second)));
    });

    test('uses the injected randomness, so salts can be reproducible', () {
      final fixed = Pbkdf2PasswordHasher(random: _FixedRandom());
      expect(fixed.createSalt(), Uint8List(16));
      expect(fixed.createSalt(), Uint8List(16));
    });

    test('defaults to 100000 iterations', () {
      expect(Pbkdf2PasswordHasher.defaultIterations, 100000);
    });

    test('checks a password in under a second (NFR-1)', () {
      final storedSalt = hasher.createSalt();
      final hash = hasher.derive(
        'a realistic password',
        salt: storedSalt,
        iterations: Pbkdf2PasswordHasher.defaultIterations,
      );

      final stopwatch = Stopwatch()..start();
      final unlocked = hasher.matches(
        'a realistic password',
        salt: storedSalt,
        iterations: Pbkdf2PasswordHasher.defaultIterations,
        expectedHash: hash,
      );
      stopwatch.stop();

      expect(unlocked, isTrue);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'checking must fit the NFR-1 budget',
      );
    });
  });

  group('constantTimeEquals', () {
    test('accepts identical bytes', () {
      expect(constantTimeEquals(Uint8List(0), Uint8List(0)), isTrue);
      expect(constantTimeEquals(_bytes('same'), _bytes('same')), isTrue);
    });

    test('rejects a difference at every position', () {
      final original = _bytes('0123456789');
      for (var i = 0; i < original.length; i++) {
        final tampered = Uint8List.fromList(original);
        tampered[i] ^= 0x80;
        expect(constantTimeEquals(original, tampered), isFalse);
      }
    });

    test('rejects different lengths', () {
      expect(constantTimeEquals(_bytes('root'), _bytes('roots')), isFalse);
      expect(constantTimeEquals(_bytes('root'), Uint8List(3)), isFalse);
    });
  });
}

/// Encodes [password] as UTF-8, matching [Pbkdf2PasswordHasher].
Uint8List _bytes(String password) =>
    Uint8List.fromList(utf8.encode(password));

Uint8List _bytesFromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

/// Always returns zero, so salt generation is observable.
class _FixedRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}
