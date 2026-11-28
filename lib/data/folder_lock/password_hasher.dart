import 'dart:typed_data';

/// Turns a password into the bytes stored in a folder's lock record,
/// and checks a typed password against them.
///
/// The plaintext password never leaves the caller: only the salt, the
/// iteration count and the derived [Uint8List] are stored (PRD NFR-5, NFR-7).
abstract interface class PasswordHasher {
  /// The cost, in iterations, that a newly written record should store.
  ///
  /// The use case reads this instead of naming a number, so the adapter owns
  /// the one knob that decides how long a check takes (PRD NFR-1).
  int get iterations;

  /// Returns a fresh random salt.
  Uint8List createSalt();

  /// Derives [hashLength] bytes from [password] and [salt], repeating the
  /// underlying function [iterations] times.
  ///
  /// The salt and iteration count are stored beside the result so that old
  /// records keep working when the default cost is raised.
  Uint8List derive(
    String password, {
    required Uint8List salt,
    required int iterations,
  });

  /// Whether [password] reproduces [expectedHash] with [salt] and [iterations].
  ///
  /// Implementations compare in constant time, so the position of a
  /// difference does not change how long the check takes.
  bool matches(
    String password, {
    required Uint8List salt,
    required int iterations,
    required Uint8List expectedHash,
  });
}
