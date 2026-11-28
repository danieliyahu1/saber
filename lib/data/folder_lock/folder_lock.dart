import 'dart:convert';
import 'dart:typed_data';

/// The record stored inside a locked folder.
///
/// It holds only what a later password check needs: the format [version], the
/// random [salt], the [iterations] cost and the derived [hash]. The password
/// itself is never written down (PRD NFR-5).
final class FolderLock {
  /// The only format this build writes. A record carrying anything else is
  /// reported as corrupt rather than guessed at.
  static const currentVersion = 1;

  final int version;
  final Uint8List salt;
  final int iterations;
  final Uint8List hash;

  new({
    required this.salt,
    required this.iterations,
    required this.hash,
    this.version = currentVersion,
  });

  /// The record as it is stored on disk.
  String encode() => jsonEncode(toJson());

  /// The record as a JSON object, before encoding.
  Map<String, Object> toJson() => {
    'v': version,
    'salt': base64Encode(salt),
    'iterations': iterations,
    'hash': base64Encode(hash),
  };

  /// Reads [contents] as a record.
  ///
  /// Unreadable data is reported as [FolderLockCorrupt], never thrown: a
  /// folder whose lock cannot be understood must look locked, and the app
  /// must not crash deciding that (PRD NFR-8).
  static FolderLockRead read(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return const FolderLockCorrupt('not JSON');
    }
    if (json is! Map<String, Object?>) {
      return const FolderLockCorrupt('not an object');
    }

    final version = json['v'];
    if (version is! int) return const FolderLockCorrupt('missing version');
    if (version != currentVersion) {
      return FolderLockCorrupt('unsupported version $version');
    }

    final salt = _decodeBytes(json['salt']);
    if (salt == null) return const FolderLockCorrupt('invalid salt');

    final iterations = json['iterations'];
    if (iterations is! int || iterations < 1) {
      return const FolderLockCorrupt('invalid iterations');
    }

    final hash = _decodeBytes(json['hash']);
    if (hash == null) return const FolderLockCorrupt('invalid hash');

    return FolderLockFound(
      FolderLock(salt: salt, iterations: iterations, hash: hash),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FolderLock &&
      other.version == version &&
      other.iterations == iterations &&
      _sameBytes(other.salt, salt) &&
      _sameBytes(other.hash, hash);

  @override
  int get hashCode => Object.hash(
    version,
    iterations,
    Object.hashAll(salt),
    Object.hashAll(hash),
  );
}

/// The outcome of reading a lock record.
sealed class FolderLockRead {
  const new();
}

/// A record that was understood.
final class FolderLockFound extends FolderLockRead {
  final FolderLock lock;
  const new(this.lock);
}

/// A record that was not understood. [reason] is for logs and tests only; the
/// person typing a password is told the same thing either way.
final class FolderLockCorrupt extends FolderLockRead {
  final String reason;
  const new(this.reason);
}

/// The bytes a base64 field holds, or null when it is absent or malformed.
Uint8List? _decodeBytes(Object? value) {
  if (value is! String) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
