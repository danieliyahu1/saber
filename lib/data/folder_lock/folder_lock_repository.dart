import 'package:saber/data/folder_lock/folder_lock.dart';

/// Where a locked folder keeps its record.
///
/// The use case depends on this instead of on files, so the lock rules can be
/// tested without touching the disk, and the adapter alone knows the record's
/// file name.
abstract interface class FolderLockRepository {
  /// The record stored in [folderPath], or null when the folder has none.
  ///
  /// An unreadable record is [FolderLockCorrupt], never null: a folder whose
  /// lock cannot be read must still look locked (PRD NFR-8).
  Future<FolderLockRead?> read(String folderPath);

  /// Stores [lock] in [folderPath].
  Future<FolderLockWriteResult> write(String folderPath, FolderLock lock);

  /// Removes the record in [folderPath] if there is one.
  ///
  /// Returns whether no record remains, so a failed delete can leave the
  /// folder locked instead of silently opening it.
  Future<bool> delete(String folderPath);

  /// Whether [folderPath] carries a lock record.
  Future<bool> exists(String folderPath);
}

/// The outcome of writing a lock record.
sealed class FolderLockWriteResult {
  const new();
}

/// The record is on disk.
final class FolderLockWritten extends FolderLockWriteResult {
  const new();
}

/// The record could not be written, so the folder must not report as locked.
final class FolderLockWriteFailed extends FolderLockWriteResult {
  /// Why the write failed, for logs and tests only.
  final String reason;
  const new(this.reason);
}
