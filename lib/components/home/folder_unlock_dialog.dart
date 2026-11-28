import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/unlock_folder_screen.dart';

/// The password screen, asked for an action instead of a view.
///
/// Some actions read a note or take it out of its folder — exporting, moving.
/// A locked note must not go through those without its folder's password
/// (PRD FR-17, NFR-6), so the same screen is asked first (FR-18) and the action
/// runs only once the folder is open.
class FolderUnlockDialog extends StatelessWidget {
  const new({super.key, required this.folderPath});

  /// The folder, or a note inside one, the action needs open.
  final String folderPath;

  /// Whether [path] may be used right now, asking for the password that covers
  /// it when it is locked.
  ///
  /// [path] is a note an action would read or move, or a folder the person
  /// tries to enter (PRD FR-10, FR-16). True means nothing locks the path, or
  /// its folder was opened — now or earlier in this session. False means the
  /// person cancelled or did not get in, so the action must not go ahead.
  static Future<bool> ensureOpen(BuildContext context, String path) async {
    final service = FolderLockScope.maybeOf(context);
    if (service == null) return true;
    if (await service.isOpen(path)) return true;
    if (!context.mounted) return false;

    final opened = await showDialog<bool>(
      context: context,
      builder: (context) => FolderUnlockDialog(folderPath: path),
    );
    if (opened != true) return false;

    // The dialog opened the folder; believe the session rather than the
    // return value alone, so "nothing locks this any more" also passes.
    return service.isOpen(path);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 360,
        child: UnlockFolderScreen(
          folderPath: folderPath,
          onUnlocked: (_) => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}
