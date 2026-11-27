import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/folder_lock/folder_lock.dart';
import 'package:saber/data/folder_lock/folder_lock_repository.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';

/// [FolderLockRepository] backed by [FileManager], and the only unit that
/// knows where the record lives.
///
/// The record is a dotfile inside the folder, so a folder listing never shows
/// it as a note, and it moves and syncs with the folder (HLD §4).
final class FileFolderLockRepository implements FolderLockRepository {
  /// The name of the record, beside the notes it protects.
  static const fileName = '.saberlock';

  const new();

  @override
  Future<FolderLockRead?> read(String folderPath) async {
    final recordPath = _recordPath(folderPath);
    if (!FileManager.doesFileExist(recordPath)) return null;

    final Uint8List? contents;
    try {
      contents = await FileManager.readFile(recordPath);
    } on FileSystemException catch (error) {
      return FolderLockCorrupt('unreadable record: ${error.message}');
    }
    if (contents == null) {
      // Either the file vanished between the check and the read, or it is
      // empty. Both mean the lock cannot be checked, so fail closed.
      return const FolderLockCorrupt('empty record');
    }

    return FolderLock.read(utf8.decode(contents, allowMalformed: true));
  }

  @override
  Future<FolderLockWriteResult> write(
    String folderPath,
    FolderLock lock,
  ) async {
    final recordPath = _recordPath(folderPath);
    if (!FileManager.getFile(recordPath).parent.existsSync()) {
      return const FolderLockWriteFailed('folder does not exist');
    }

    try {
      await FileManager.writeFile(
        recordPath,
        utf8.encode(lock.encode()),
        awaitWrite: true,
        trackAsRecent: false,
      );
      return const FolderLockWritten();
    } on FileSystemException catch (error) {
      // Disk full, read-only storage, or a clash at the record's path.
      return FolderLockWriteFailed(error.message);
    }
  }

  @override
  Future<bool> delete(String folderPath) async {
    final recordPath = _recordPath(folderPath);
    try {
      if (!FileManager.doesFileExist(recordPath)) {
        // No local copy, but a synced one may exist, so enqueue the same
        // delete FileManager would have. The syncer ignores this offline.
        await syncer.uploader.enqueueRel(recordPath);
        return true;
      }

      await FileManager.deleteFile(recordPath);
      return !FileManager.doesFileExist(recordPath);
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<bool> exists(String folderPath) async =>
      FileManager.doesFileExist(_recordPath(folderPath));

  /// The record's path inside [folderPath], ignoring a trailing slash.
  String _recordPath(String folderPath) {
    final folder = folderPath.length > 1 && folderPath.endsWith('/')
        ? folderPath.substring(0, folderPath.length - 1)
        : folderPath;
    return '$folder/$fileName';
  }
}
