import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/lock_folder_dialog.dart';
import 'package:saber/i18n/strings.g.dart';

/// The folder menu entry that puts a password on an unlocked folder
/// (PRD FR-1, FR-33).
///
/// A locked folder does not get this entry: its menu offers Remove lock
/// instead (FR-4). Until that exists, the entry is simply absent.
class LockFolderButton extends StatelessWidget {
  const new({super.key, required this.folderPath});

  final String folderPath;

  @override
  Widget build(BuildContext context) {
    final service = FolderLockScope.of(context);

    return FutureBuilder<bool>(
      future: service.isLocked(folderPath),
      builder: (context, snapshot) {
        // Nothing while the question is open, and nothing once it is locked.
        if (snapshot.data != false) return const SizedBox.shrink();

        return IconButton(
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
      },
    );
  }
}

extension on TargetPlatform {
  /// Whether this is a device where a lock can be removed by hand.
  bool get isComputer => switch (this) {
    .windows || .linux || .macOS => true,
    .android || .iOS || .fuchsia => false,
  };
}
