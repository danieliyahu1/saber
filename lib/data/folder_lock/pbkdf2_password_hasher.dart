import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';

/// [PasswordHasher] backed by PBKDF2-HMAC-SHA256, the construction named by
/// the Folder Lock HLD (§5).
///
/// Salts are 16 random bytes and derived values are 32 bytes. A check is a
/// single derivation followed by a constant-time comparison, which keeps
/// every stored record self-describing: raising [defaultIterations] never
/// invalidates an existing lock.
class Pbkdf2PasswordHasher implements PasswordHasher {
  /// The cost of a new lock, in PBKDF2 iterations.
  ///
  /// Tuned to stay far inside the one-second budget of PRD NFR-1 on a
  /// mid-range phone; the derivation is deliberately expensive, so this is
  /// the only knob that decides how long a check takes.
  static const defaultIterations = 100000;

  /// Length of a generated salt, in bytes.
  static const saltLength = 16;

  /// Length of a derived value, in bytes.
  static const hashLength = 32;

  /// HMAC-SHA256 hashes 64-byte blocks, so PBKDF2 needs 64 as its PRF block
  /// length. (Dart's `HMac` does not infer it.)
  static const _hmacBlockLength = 64;

  final Random _random;

  /// Uses a cryptographically secure source unless [random] is supplied,
  /// which exists only so tests can make salts reproducible.
  new({Random? random}) : _random = random ?? Random.secure();

  @override
  int get iterations => defaultIterations;

  @override
  Uint8List createSalt() {
    final salt = Uint8List(saltLength);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }

  @override
  Uint8List derive(
    String password, {
    required Uint8List salt,
    required int iterations,
  }) {
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'must be at least 1');
    }
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), _hmacBlockLength))
      ..init(Pbkdf2Parameters(salt, iterations, hashLength));
    return derivator.process(_passwordBytes(password));
  }

  @override
  bool matches(
    String password, {
    required Uint8List salt,
    required int iterations,
    required Uint8List expectedHash,
  }) {
    final actualHash = derive(password, salt: salt, iterations: iterations);
    return constantTimeEquals(actualHash, expectedHash);
  }

  /// Encodes exactly what was typed: no trimming, case folding or unicode
  /// normalisation may happen before hashing (PRD PW-1, PW-3).
  static Uint8List _passwordBytes(String password) =>
      Uint8List.fromList(utf8.encode(password));
}

/// Whether [a] and [b] hold the same bytes, without stopping at the first
/// difference. Lengths are compared first because they are not secret.
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
