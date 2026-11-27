import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/preview_card.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// The whole flow from the PRD's "Owner — protect one folder": a folder with a
/// real note in it, locked through the menu and dialog, then opened again.
///
/// The lock records live in memory here: real asynchronous file IO cannot
/// complete inside a widget test's fake clock. The repository itself, and the
/// real on-disk record, are covered by `file_folder_lock_repository_test`.
void main() {
  const folderName = 'folder_lock_flow_test';
  const folder = '/$folderName';
  const notePath = '$folder/entry.sbn2';
  const previewPath = '$notePath.p';
  const password = 'hunter2';
  const dialogBody =
      'Choose a password for this folder. '
      'You will need it to see what is inside.';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    await FileManager.deleteDirectory(folder);
    await FileManager.createFolder(folder);
    await FileManager.writeFile(notePath, [1], awaitWrite: true);
    stows.recentFiles.value = [];
    stows.sentryConsent.value = .granted;

    BrowsePage.overrideChildren = DirectoryChildren(const [
      folderName,
    ], const []);

    repository = MemoryFolderLockRepository();
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() async {
    service.dispose();
    BrowsePage.overrideChildren = null;
    await FileManager.deleteDirectory(folder);
    stows.recentFiles.value = [];
  });

  testWidgets('lock a folder through the UI, then it opens locked', (
    tester,
  ) async {
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text(folderName), findsOneWidget);

    await tester.longPress(find.text(folderName));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Lock folder'));
    await tester.pumpAndSettle();
    expect(find.text(dialogBody), findsOneWidget);

    // Empty and short passwords are refused without closing the dialog.
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a password.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 4 characters.'), findsOneWidget);
    expect(await service.isLocked(folder), isFalse);

    // Cancelling leaves the folder unlocked.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await service.isLocked(folder), isFalse);
    expect(find.byTooltip('Locked'), findsNothing);

    // Lock it for real.
    await tester.tap(find.byTooltip('Lock folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    expect(await service.isLocked(folder), isTrue);
    expect(find.byTooltip('Locked'), findsOneWidget);
    expect(
      FileManager.doesFileExist(previewPath),
      isFalse,
      reason: 'locking writes the record, never a preview',
    );

    // Reopening the app at the folder: the contents are not shown, and no
    // preview card is even built.
    BrowsePage.overrideChildren = DirectoryChildren(const [], const ['entry']);
    await tester.pumpWidget(_app(service, path: folder));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('entry'), findsNothing);
    expect(find.byType(PreviewCard), findsNothing);

    // The password opens it, in the same view.
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('entry'), findsOneWidget);
  });
}

Widget _app(FolderLockService service, {String? path}) {
  final router = GoRouter(
    initialLocation: HomeRoutes.browseFilePath(path),
    routes: [
      GoRoute(
        path: RoutePaths.home,
        builder: (context, state) =>
            BrowsePage(path: state.uri.queryParameters['path']),
      ),
    ],
  );
  return FolderLockScope(
    service: service,
    child: MaterialApp.router(routerConfig: router),
  );
}
