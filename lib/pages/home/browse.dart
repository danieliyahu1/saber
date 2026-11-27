import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/no_files.dart';
import 'package:saber/components/home/path_components.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/syncing_button.dart';
import 'package:saber/components/home/unlock_folder_screen.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';

class BrowsePage extends StatefulHookWidget {
  const new({super.key, String? path}) : initialPath = path;

  final String? initialPath;

  @visibleForTesting
  static DirectoryChildren? overrideChildren;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  DirectoryChildren? children;

  String? path;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  FolderLockService? _folderLockService;

  /// Null while the lock is being resolved, so contents are never built
  /// before the answer is known (FR-10, FR-23).
  bool? _contentsMayBeShown;

  var _lockCheck = 0;

  @override
  void initState() {
    path = widget.initialPath;

    findChildrenOfPath();
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_setState);

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _folderLockService = FolderLockScope.of(context);
    _checkLock();
  }

  @override
  void dispose() {
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (!event.filePath.startsWith(path ?? '/')) return;
    findChildrenOfPath(fromFileListener: true);
  }

  void _setState() => setState(() {});

  /// Asks the service whether the current folder may be shown.
  ///
  /// The last check wins, so a slow answer for an old path cannot overwrite a
  /// newer one. While the answer is unknown nothing is rendered.
  Future<void> _checkLock() async {
    final check = ++_lockCheck;
    final mayBeShown = await _folderLockService!.isOpen(path ?? '/');
    if (!mounted || check != _lockCheck) return;
    if (_contentsMayBeShown != mayBeShown) {
      setState(() => _contentsMayBeShown = mayBeShown);
    }
  }

  /// Resolves the lock before moving, so the new folder is either shown or
  /// gated — never flashed and then hidden.
  Future<void> _goTo(String? newPath) async {
    final mayBeShown = await _folderLockService!.isOpen(newPath ?? '/');
    if (!mounted) return;

    setState(() {
      path = newPath;
      _contentsMayBeShown = mayBeShown;
    });
    context.go(HomeRoutes.browseFilePath(newPath ?? '/'));
    findChildrenOfPath();
  }

  Future findChildrenOfPath({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      // don't refresh if we're not on the home page
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
    }

    children =
        BrowsePage.overrideChildren ??
        await FileManager.getChildrenOfDirectory(
          path ?? '/',
          sortMetric: stows.browseSortMetric.value,
        );

    if (mounted) setState(() {});
  }

  void onDirectoryTap(String folder) {
    selectedFiles.value = [];
    if (folder == '..') {
      final parent = p.dirname(path ?? '/');
      _goTo(parent == '/' ? null : parent);
    } else {
      _goTo(p.join(path ?? '/', folder));
    }
  }

  void onPathComponentTap(String? newPath) {
    selectedFiles.value = [];
    if (newPath == null || newPath.isEmpty || newPath == '/') {
      newPath = null;
    }
    _goTo(newPath);
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';
    await FileManager.createFolder(folderPath);
    findChildrenOfPath();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final crossAxisCount = MediaQuery.sizeOf(context).width ~/ 300 + 1;
    useListenable(stows.homeLayout);
    useOnListenableChange(stows.browseSortMetric, findChildrenOfPath);

    if (_contentsMayBeShown != true) {
      return Scaffold(
        body: _contentsMayBeShown == false
            ? UnlockFolderScreen(
                folderPath: path ?? '/',
                onUnlocked: (_) => _checkLock(),
              )
            // Resolving the lock; rendering nothing here is what keeps a
            // locked folder's contents out of the tree entirely.
            : const SizedBox.shrink(),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            collapsedHeight: kToolbarHeight,
            expandedHeight: platform.isMaterialNative ? 200 - 8 : null,
            pinned: true,
            scrolledUnderElevation: 1,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                t.home.titles.browse,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 8, // less than other pages for path components
              ),
            ),
            actions: const [
              BrowseSortButton(),
              HomeLayoutButton(),
              SyncingButton(),
            ],
          ),
          SliverToBoxAdapter(
            child: PathComponents(path, onPathComponentTap: onPathComponentTap),
          ),
          const SliverPadding(padding: .only(bottom: 16)),
          GridFolders(
            isAtRoot: path?.isEmpty ?? true,
            crossAxisCount: crossAxisCount,
            parentPath: path,
            onTap: onDirectoryTap,
            createFolder: createFolder,
            doesFolderExist: (String folderName) {
              return children?.directories.contains(folderName) ?? false;
            },
            renameFolder: (String oldName, String newName) async {
              final oldPath = '${path ?? ''}/$oldName';
              await FileManager.renameDirectory(oldPath, newName);
              findChildrenOfPath();
            },
            isFolderEmpty: (String folderName) async {
              final folderPath = '${path ?? ''}/$folderName';
              final children = await FileManager.getChildrenOfDirectory(
                folderPath,
              );
              return children?.isEmpty ?? true;
            },
            deleteFolder: (String folderName) async {
              final folderPath = '${path ?? ''}/$folderName';
              await FileManager.deleteDirectory(folderPath);
              findChildrenOfPath();
            },
            folders: [
              for (final directoryPath in children?.directories ?? const [])
                directoryPath,
            ],
          ),
          if (children == null) ...[
            // loading
          ] else if (children!.isEmpty) ...[
            const SliverSafeArea(sliver: SliverToBoxAdapter(child: NoFiles())),
          ] else ...[
            SliverSafeArea(
              top: false,
              minimum: const .only(
                top: 8,
                // Allow space for the FloatingActionButton
                bottom: 70,
              ),
              sliver: MasonryFiles(
                crossAxisCount: crossAxisCount,
                files: [
                  for (final filePath in children?.files ?? const [])
                    "${path ?? ""}/$filePath",
                ],
                selectedFiles: selectedFiles,
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: NewNoteButton(
        cupertino: platform.isCupertino,
        path: path,
      ),
      persistentFooterButtons: selectedFiles.value.isEmpty
          ? null
          : [
              Collapsible(
                axis: .vertical,
                collapsed: selectedFiles.value.length != 1,
                child: RenameNoteButton(
                  existingPath: selectedFiles.value.isEmpty
                      ? ''
                      : selectedFiles.value.first,
                  unselectNotes: () => selectedFiles.value = [],
                ),
              ),
              MoveNoteButton(
                filesToMove: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              DeleteNoteButton(
                filesToDelete: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              ExportNoteButton(selectedFiles: selectedFiles.value),
            ],
    );
  }
}
