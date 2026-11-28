import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/folder_unlock_dialog.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class MoveNoteButton extends StatelessWidget {
  const new({
    super.key,
    required this.filesToMove,
    required this.unselectNotes,
    this.childrenOf,
  });

  final List<String> filesToMove;
  final void Function() unselectNotes;

  /// Lists a folder's children for the picker.
  ///
  /// Real directory reads do not complete inside a widget test's clock, so
  /// tests pass their own listing. Production uses [FileManager].
  @visibleForTesting
  final Future<DirectoryChildren?> Function(String folder)? childrenOf;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: .zero,
      tooltip: t.home.moveNote.moveNote,
      onPressed: () async {
        // Moving a locked note out of its folder exposes it (PRD NFR-6), and
        // the dialog lists folder names, so open the notes' folder first.
        for (final filePath in filesToMove) {
          if (!await FolderUnlockDialog.ensureOpen(context, filePath)) return;
        }
        if (!context.mounted) return;

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return _MoveNoteDialog(
              filesToMove: filesToMove,
              unselectNotes: unselectNotes,
              childrenOf: childrenOf ?? FileManager.getChildrenOfDirectory,
            );
          },
        );
      },
      icon: const Icon(Icons.drive_file_move),
    );
  }
}

class _MoveNoteDialog extends StatefulWidget {
  const new({
    required this.filesToMove,
    required this.unselectNotes,
    required this.childrenOf,
  });

  final List<String> filesToMove;
  final void Function() unselectNotes;
  final Future<DirectoryChildren?> Function(String folder) childrenOf;

  @override
  State<_MoveNoteDialog> createState() => _MoveNoteDialogState();
}

class _MoveNoteDialogState extends State<_MoveNoteDialog> {
  /// The original file names of the notes.
  late final List<String> originalFileNames = widget.filesToMove
      .map((path) => path.substring(path.lastIndexOf('/') + 1))
      .toList();

  /// The original parent folders of the notes,
  /// including the trailing slash.
  late final List<String> parentFolders = widget.filesToMove
      .map((path) => path.substring(0, path.lastIndexOf('/') + 1))
      .toList();

  /// Whether each file uses [Editor.extensionOldJson].
  /// This is populated in [findOldExtensions].
  late List<bool> oldExtensions = widget.filesToMove
      .map((name) => false)
      .toList();
  Future<void> findOldExtensions() async {
    oldExtensions = [
      for (int i = 0; i < widget.filesToMove.length; ++i)
        FileManager.doesFileExist(
          '${widget.filesToMove[i]}${Editor.extensionOldJson}',
        ),
    ];
  }

  late String _currentFolder;

  /// The current folder browsed to in the dialog.
  String get currentFolder => _currentFolder;
  set currentFolder(String folder) {
    _currentFolder = folder;
    currentFolderChildren = null;
    findChildrenOfCurrentFolder();
  }

  /// The children of [currentFolder].
  DirectoryChildren? currentFolderChildren;

  /// The file names that the notes will be moved to.
  ///
  /// These will be the same as in [fileNames], unless
  /// a file needs to be renamed to avoid a name conflict.
  /// Such a file will also be in [changedFileNames].
  late List<String> newFileNames = [];

  /// The new names of the files that needed to be renamed.
  late List<String> changedFileNames = [];

  Future findChildrenOfCurrentFolder() async {
    currentFolderChildren = await widget.childrenOf(currentFolder);

    newFileNames = [];
    changedFileNames = [];
    for (int i = 0; i < widget.filesToMove.length; ++i) {
      final oldExtension = oldExtensions[i];
      final newFileName = await FileManager.suffixFilePathToMakeItUnique(
        '$currentFolder${originalFileNames[i]}',
        intendedExtension: oldExtension
            ? Editor.extensionOldJson
            : Editor.extension,
        currentPath:
            '${widget.filesToMove[i]}${oldExtension ? Editor.extensionOldJson : Editor.extension}',
      ).then((newPath) => newPath.substring(newPath.lastIndexOf('/') + 1));

      newFileNames.add(newFileName);

      if (newFileName != originalFileNames[i]) {
        changedFileNames.add(newFileName);
      }
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = '$currentFolder/$folderName';
    await FileManager.createFolder(folderPath);
    findChildrenOfCurrentFolder();
  }

  @override
  void initState() {
    currentFolder = _findMostCommonParentFolder();
    if (!currentFolder.startsWith('/')) {
      currentFolder = '/$currentFolder';
    }
    super.initState();

    findOldExtensions().then((_) => findChildrenOfCurrentFolder());
  }

  String _findMostCommonParentFolder() {
    final parentFolderCounts = <String, int>{};
    for (final parentFolder in parentFolders) {
      parentFolderCounts[parentFolder] =
          (parentFolderCounts[parentFolder] ?? 0) + 1;
    }
    return parentFolderCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: originalFileNames.length < 5
          ? Text(t.home.moveNote.moveName(f: originalFileNames.join(', ')))
          : Text(t.home.moveNote.moveNotes(n: originalFileNames.length)),
      content: SizedBox(
        width: 300,
        height: 300,
        child: Column(
          children: [
            Text(currentFolder),
            Expanded(
              child: CustomScrollView(
                shrinkWrap: true,
                slivers: [
                  GridFolders(
                    isAtRoot: currentFolder == '/',
                    crossAxisCount: 3,
                    parentPath: currentFolder,
                    onTap: (String folder) async {
                      if (folder == '..') {
                        setState(() {
                          currentFolder = currentFolder.substring(
                            0,
                            currentFolder.lastIndexOf(
                                  '/',
                                  currentFolder.length - 2,
                                ) +
                                1,
                          );
                        });
                        return;
                      }

                      final target = '$currentFolder$folder/';
                      // A locked folder shows its password screen instead of
                      // its contents, the picker included (PRD FR-10).
                      if (!await FolderUnlockDialog.ensureOpen(
                        context,
                        target,
                      )) {
                        return;
                      }
                      if (!mounted) return;
                      setState(() => currentFolder = target);
                    },
                    createFolder: createFolder,
                    doesFolderExist: (String folderName) {
                      return currentFolderChildren?.directories.contains(
                            folderName,
                          ) ??
                          false;
                    },
                    renameFolder: (String oldName, String newName) async {
                      final lockService = FolderLockScope.maybeOf(context);
                      final oldPath = '$currentFolder$oldName';
                      final newPath = await FileManager.renameDirectory(
                        oldPath,
                        newName,
                      );
                      lockService?.folderMoved(from: oldPath, to: newPath);
                      findChildrenOfCurrentFolder();
                    },
                    isFolderEmpty: (String folderName) async {
                      final folderPath = '$currentFolder$folderName';
                      final children = await FileManager.getChildrenOfDirectory(
                        folderPath,
                      );
                      return children?.isEmpty ?? true;
                    },
                    deleteFolder: (String folderName) async {
                      final folderPath = '$currentFolder$folderName';
                      await FileManager.deleteDirectory(folderPath);
                      findChildrenOfCurrentFolder();
                    },
                    folders: [
                      for (final directoryPath
                          in currentFolderChildren?.directories ?? const [])
                        directoryPath,
                    ],
                  ),
                ],
              ),
            ),
            if (changedFileNames.isEmpty)
              const SizedBox.shrink()
            else if (changedFileNames.length == 1)
              Text(t.home.moveNote.renamedTo(newName: changedFileNames.single))
            else if (changedFileNames.length < 5) ...[
              Text(t.home.moveNote.multipleRenamedTo),
              Text(changedFileNames.join(', ')),
            ] else
              Text(t.home.moveNote.numberRenamedTo(n: changedFileNames.length)),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(t.common.cancel),
        ),
        CupertinoDialogAction(
          onPressed: () async {
            // The session can close while this dialog is open (PRD FR-28), so
            // the sources are checked again right before they move.
            for (final filePath in widget.filesToMove) {
              if (!await FolderUnlockDialog.ensureOpen(context, filePath)) {
                return;
              }
            }
            if (!mounted) return;

            for (int i = 0; i < widget.filesToMove.length; ++i) {
              final extension = oldExtensions[i]
                  ? Editor.extensionOldJson
                  : Editor.extension;
              await FileManager.moveFile(
                '${widget.filesToMove[i]}$extension',
                '$currentFolder${newFileNames[i]}$extension',
              );
            }
            widget.unselectNotes();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
          child: Text(t.home.moveNote.move),
        ),
      ],
    );
  }
}
