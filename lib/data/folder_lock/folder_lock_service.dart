import 'package:flutter/foundation.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_policy.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/folder_lock/password_hasher.dart';

/// Puts passwords on folders, and remembers which ones are open right now.
///
/// Widgets ask this, never the repository: the password rules, the hashing and
/// the "a locked folder stays as it is" rule live here (PRD FR-1…FR-3,
/// PW-1…PW-4). It notifies listeners whenever a lock appears or disappears so
/// that badges and listings can refresh without a manual reload (PRD FR-6).
///
/// Unlocking is a session fact only: the set of open folders lives in memory
/// for the life of the process and is never written down (PRD FR-14, FR-32).
class FolderLockService extends ChangeNotifier {
  /// The shortest password the PRD allows (PW-2).
  static const minimumPasswordLength = 4;

  /// Shown when the field is submitted empty (FR-41).
  static const emptyPasswordMessage = 'Enter a password.';

  /// Shown when the password is too short (PW-2, FR-41).
  static const shortPasswordMessage = 'Use at least 4 characters.';

  /// Shown for every failed attempt, including an unreadable record (FR-46,
  /// NFR-8).
  static const wrongPasswordMessage = 'Wrong password.';

  final FolderLockRepository _repository;
  final PasswordHasher _hasher;

  /// Folders whose lock was satisfied in this session. Keyed by the locked
  /// folder itself, never by the note or subfolder that asked.
  final _unlockedFolders = <String>{};

  new({required this._repository, required this._hasher});

  /// Locks [folderPath] with [password].
  ///
  /// An already locked folder is left exactly as it was: changing a password
  /// is out of scope (PRD §Scope), and a second record would make the answer
  /// to "which password opens this?" depend on the order of writes.
  Future<LockFolderResult> lock(String folderPath, String password) async {
    final refusal = _refusalFor(password);
    if (refusal != null) return LockPasswordRejected(refusal);

    final folder = FolderLockPolicy.normalise(folderPath);
    if (await _repository.exists(folder)) {
      return const FolderAlreadyLocked();
    }

    final salt = _hasher.createSalt();
    final lock = FolderLock(
      salt: salt,
      iterations: _hasher.iterations,
      hash: _hasher.derive(
        password,
        salt: salt,
        iterations: _hasher.iterations,
      ),
    );

    final written = await _repository.write(folder, lock);
    if (written is FolderLockWriteFailed) {
      return LockSaveFailed(written.reason);
    }

    notifyListeners();
    return const FolderLocked();
  }

  /// Opens the locked folder that covers [folderPath], if [password] is right.
  ///
  /// Called with a note's path it unlocks the note's folder and returns that
  /// folder, so the caller can open the note next (FR-13, FR-16). Nothing is
  /// remembered on disk.
  Future<UnlockFolderResult> unlock(String folderPath, String password) async {
    final lockedFolder = await _coveringLock(folderPath);
    if (lockedFolder == null) return const NothingToUnlock();

    final record = await _repository.read(lockedFolder);
    if (record is! FolderLockFound) {
      // Missing or unreadable while a lock is believed to exist: stay closed
      // and say the same thing as a wrong password (FR-46, NFR-8).
      return const UnlockRefused(wrongPasswordMessage);
    }

    final lock = record.lock;
    final matches = _hasher.matches(
      password,
      salt: lock.salt,
      iterations: lock.iterations,
      expectedHash: lock.hash,
    );
    if (!matches) return const UnlockRefused(wrongPasswordMessage);

    _unlockedFolders.add(lockedFolder);
    notifyListeners();
    return FolderUnlocked(lockedFolder);
  }

  /// Removes the lock covering [folderPath], if [password] is right.
  ///
  /// Removal is the one way back from a forgotten password on a computer, so
  /// it is gated by the same check as unlocking (FR-4, FR-5). A failed delete
  /// leaves the record, and therefore the lock, in place.
  Future<RemoveLockResult> remove(String folderPath, String password) async {
    final lockedFolder = await _coveringLock(folderPath);
    if (lockedFolder == null) return const RemoveNotLocked();

    final record = await _repository.read(lockedFolder);
    if (record is! FolderLockFound) {
      return record == null
          ? const RemoveNotLocked()
          : const RemoveCorruptLock();
    }

    final lock = record.lock;
    final matches = _hasher.matches(
      password,
      salt: lock.salt,
      iterations: lock.iterations,
      expectedHash: lock.hash,
    );
    if (!matches) return const RemoveWrongPassword(wrongPasswordMessage);

    final removed = await _repository.delete(lockedFolder);
    if (!removed) return const RemoveFailed('the record could not be deleted');

    _unlockedFolders.remove(lockedFolder);
    notifyListeners();
    return const LockRemoved();
  }

  /// The lock record that covers [folderPath], or null when nothing does.
  Future<String?> _coveringLock(String folderPath) =>
      FolderLockPolicy.nearestLockedAncestor(folderPath, _repository.exists);

  /// Whether [folderPath] itself carries a lock record.
  ///
  /// A lock on a parent does not make a child "locked" for display: FR-6
  /// marks the folder that was locked, and a child's own mark would say
  /// something untrue about it.
  Future<bool> isLocked(String folderPath) =>
      _repository.exists(FolderLockPolicy.normalise(folderPath));

  /// Whether [folderPath]'s contents may be shown right now.
  ///
  /// True when nothing locks the path, or when its nearest locked folder was
  /// unlocked in this session. Unlocking a parent opens everything beneath it;
  /// unlocking a child opens only the child (FR-14, FR-15).
  Future<bool> isOpen(String folderPath) async {
    await _forgetUnlocksWithoutRecords();

    final lockedFolder = await FolderLockPolicy.nearestLockedAncestor(
      folderPath,
      _repository.exists,
    );
    return lockedFolder == null || _unlockedFolders.contains(lockedFolder);
  }

  /// Closes every open folder. The app calls this when it is put away (FR-28).
  void relockAll() {
    if (_unlockedFolders.isEmpty) return;
    _unlockedFolders.clear();
    notifyListeners();
  }

  /// Drops session entries whose record has gone, such as a folder deleted
  /// outside the app (HLD §12).
  Future<void> _forgetUnlocksWithoutRecords() async {
    for (final folder in _unlockedFolders.toList()) {
      if (!await _repository.exists(folder)) {
        _unlockedFolders.remove(folder);
      }
    }
  }

  /// The copy to show for [password], or null when it is acceptable.
  ///
  /// Nothing is trimmed, upper-cased or otherwise changed (PW-1), and code
  /// points are counted so that an emoji is one character (PW-3).
  String? _refusalFor(String password) {
    if (password.isEmpty) return emptyPasswordMessage;
    if (password.runes.length < minimumPasswordLength) {
      return shortPasswordMessage;
    }
    return null;
  }
}

/// The outcome of locking a folder.
sealed class LockFolderResult {
  const new();
}

/// The folder is now locked.
final class FolderLocked extends LockFolderResult {
  const new();
}

/// The password was refused; [message] is the copy to show in the dialog.
final class LockPasswordRejected extends LockFolderResult {
  final String message;
  const new(this.message);
}

/// The folder already had a lock, which was not touched.
final class FolderAlreadyLocked extends LockFolderResult {
  const new();
}

/// The record could not be written, so the folder is not locked.
final class LockSaveFailed extends LockFolderResult {
  /// Why the write failed, for logs and tests only.
  final String reason;
  const new(this.reason);
}

/// The outcome of unlocking a folder or a note inside one.
sealed class UnlockFolderResult {
  const new();
}

/// [folder] is open for the rest of the session.
final class FolderUnlocked extends UnlockFolderResult {
  /// The locked folder that was opened. When the caller asked about a note,
  /// this is the note's folder, not the note.
  final String folder;
  const new(this.folder);
}

/// The password was wrong, or the record could not be read. [message] is the
/// copy to show.
final class UnlockRefused extends UnlockFolderResult {
  final String message;
  const new(this.message);
}

/// Nothing locks the path, so there was nothing to open.
final class NothingToUnlock extends UnlockFolderResult {
  const new();
}

/// The outcome of removing a lock.
sealed class RemoveLockResult {
  const new();
}

/// The lock is gone and the folder opens as before (FR-5, FR-6).
final class LockRemoved extends RemoveLockResult {
  const new();
}

/// Nothing covers the path, so there was no lock to remove. Removing twice
/// lands here too, which makes it a no-op rather than an error.
final class RemoveNotLocked extends RemoveLockResult {
  const new();
}

/// The record could not be read, so the password could not be checked and the
/// lock stays (NFR-8).
final class RemoveCorruptLock extends RemoveLockResult {
  const new();
}

/// The password was wrong; the record is untouched.
final class RemoveWrongPassword extends RemoveLockResult {
  final String message;
  const new(this.message);
}

/// The record could not be deleted, so the folder stays locked.
final class RemoveFailed extends RemoveLockResult {
  /// Why the delete failed, for logs and tests only.
  final String reason;
  const new(this.reason);
}
