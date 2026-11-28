import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

/// The whole Remove lock flow (PRD FR-4, FR-5, FR-6): lock, remove with the
/// right password, the badge goes, and the folder opens without a prompt.
void main() {
  const folderName = 'remove_lock_flow_test';
  const folder = '/$folderName';
  const password = 'hunter2';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    stows.sentryConsent.value = .granted;
    await FileManager.deleteDirectory(folder);
    await FileManager.createFolder(folder);
    await FileManager.writeFile('$folder/entry.sbn2', [1], awaitWrite: true);
    stows.recentFiles.value = [];

    BrowsePage.overrideChildren = DirectoryChildren(
      const [folderName],
      const [],
    );

    repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
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

  testWidgets('remove the lock through the menu, then open the folder', (
    tester,
  ) async {
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Locked'), findsOneWidget);

    await tester.longPress(find.text(folderName));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove lock'));
    await tester.pumpAndSettle();

    expect(find.text('Remove lock'), findsWidgets);
    expect(
      find.text('Enter the password to remove the lock from this folder.'),
      findsOneWidget,
    );

    // A wrong password leaves the folder locked.
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password.'), findsOneWidget);
    expect(await service.isLocked(folder), isTrue);

    // The right password removes it and the badge goes without a refresh.
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsNothing, reason: 'dialog closed');
    expect(await service.isLocked(folder), isFalse);
    expect(repository.locks, isEmpty);
    expect(find.byTooltip('Locked'), findsNothing);

    // The folder now opens without asking for a password.
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text(folderName));
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsNothing);

    BrowsePage.overrideChildren = DirectoryChildren(const [], const ['entry']);
    await tester.pumpWidget(_app(service, path: folder));
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
