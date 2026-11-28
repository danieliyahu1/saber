import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/lock_folder_dialog.dart';
import 'package:saber/components/home/remove_lock_dialog.dart';
import 'package:saber/i18n/strings.g.dart';

/// The folder menu entry for a folder's lock (PRD FR-1, FR-4).
///
/// An unlocked folder offers Lock folder; a locked one offers Remove lock.
/// The service's notification rebuilds this entry and the badge, so a lock or
/// a removal shows immediately (FR-6).
class LockFolderButton extends StatelessWidget {
  const new({super.key, required this.folderPath});

  final String folderPath;

  @override
  Widget build(BuildContext context) {
    final service = FolderLockScope.of(context);

    return FutureBuilder<bool>(
      future: service.isLocked(folderPath),
      builder: (context, snapshot) {
        // Nothing while the question is open.
        if (snapshot.data case final locked?) {
          return locked ? _removeLock(context) : _lock(context);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _lock(BuildContext context) => IconButton(
    padding: EdgeInsets.zero,
    tooltip: t.home.folderLock.lockFolder,
    onPressed: () => showDialog(
      context: context,
      builder: (context) => LockFolderDialog(
        folderPath: folderPath,
        isComputer: Theme.of(context).platform.isComputer,
      ),
    ),
    icon: const Icon(Icons.lock_outline),
  );

  Widget _removeLock(BuildContext context) => IconButton(
    padding: EdgeInsets.zero,
    tooltip: t.home.folderLock.removeLock,
    onPressed: () => showDialog(
      context: context,
      builder: (context) => RemoveLockDialog(folderPath: folderPath),
    ),
    icon: const Icon(Icons.lock_open),
  );
}

extension on TargetPlatform {
  /// Whether this is a device where a lock can be removed by hand.
  bool get isComputer => switch (this) {
    .windows || .linux || .macOS => true,
    .android || .iOS || .fuchsia => false,
  };
}
