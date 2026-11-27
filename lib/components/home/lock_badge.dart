import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/i18n/strings.g.dart';

/// The mark a locked folder wears wherever it is listed (PRD FR-6).
///
/// It asks the service and rebuilds when the service says something changed,
/// so locking or removing a lock updates the listing without a manual refresh.
/// It occupies the folder icon's corner, so the folder's name below it can be
/// as long as it likes without pushing the mark away.
class LockBadge extends StatelessWidget {
  const new({super.key, required this.folderPath});

  /// The folder itself, not a note inside it.
  final String folderPath;

  @override
  Widget build(BuildContext context) {
    final service = FolderLockScope.of(context);

    return FutureBuilder<bool>(
      future: service.isLocked(folderPath),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Tooltip(
          message: t.home.folderLock.locked,
          child: Semantics(
            label: t.home.folderLock.locked,
            child: Icon(
              Icons.lock,
              size: 20,
              color: ColorScheme.of(context).onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
