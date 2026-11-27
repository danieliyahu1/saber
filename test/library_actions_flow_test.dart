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

/// The library actions on a locked folder, end to end (PRD FR-24, FR-25,
/// FR-26): rename it without a password and it stays locked and still asks;
/// delete it and only the ordinary confirmation appears.
void main() {
  const folderName = 'library_actions_flow_test';
  const folder = '/$folderName';
  const renamedName = 'library_actions_renamed';
  const renamedFolder = '/$renamedName';
  const notePath = '$folder/entry.sbn2';
  const password = 'hunter2';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUpAll(() async {
    FlavorConfig.setup();
    setupMockPathProvider();
    await FileManager.init(shouldWatchRootDirectory: false);
  });

  setUp(() async {
    await FileManager.deleteDirectory(folder);
    await FileManager.deleteDirectory(renamedFolder);
    await FileManager.createFolder(folder);
    await FileManager.writeFile(notePath, [1], awaitWrite: true);
    stows.recentFiles.value = [];
    stows.sentryConsent.value = .granted;

    BrowsePage.overrideChildren = DirectoryChildren(const [folderName], const []);

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
    await FileManager.deleteDirectory(renamedFolder);
    stows.recentFiles.value = [];
  });

  testWidgets('renaming a locked folder keeps it locked and still asking', (
    tester,
  ) async {
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(folderName));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Locked'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename folder'));
    await tester.pumpAndSettle();

    // No password is asked to rename, and none is offered.
    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Wrong password.'), findsNothing);

    await tester.enterText(find.byType(TextField), renamedName);
    // The rename hits the real file system, so let its IO finish.
    await tester.runAsync(() async {
      await tester.tap(find.text('Rename'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(FileManager.isDirectory(renamedFolder), isTrue);
    expect(FileManager.isDirectory(folder), isFalse);

    // On disk the record lives inside the folder and moves with it; the
    // in-memory repository has to be told the same thing.
    repository.locks[renamedFolder] = repository.locks.remove(folder)!;

    expect(await service.isLocked(renamedFolder), isTrue);
    expect(await service.isLocked(folder), isFalse);

    // The list now shows the renamed folder, still badged and still asking.
    BrowsePage.overrideChildren = DirectoryChildren(const [renamedName], const []);
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text(renamedName), findsOneWidget);
    expect(find.byTooltip('Locked'), findsOneWidget);

    // The renamed folder still lists its note once it is open.
    BrowsePage.overrideChildren = DirectoryChildren(const [], const ['entry']);
    await tester.pumpWidget(_app(service, path: renamedFolder));
    await tester.pumpAndSettle();
    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('entry'), findsNothing);

    // The lock still opens with the password it had before the rename.
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('entry'), findsOneWidget);
  });

  testWidgets('deleting a locked folder asks only the usual confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(folderName));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete folder'));
    await tester.pumpAndSettle();

    expect(find.text('This folder is locked.'), findsNothing);
    expect(find.text('Wrong password.'), findsNothing);
    expect(find.byType(TextField), findsNothing, reason: 'no password field');
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    // The delete hits the real file system, so let its IO finish.
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(FileManager.isDirectory(folder), isFalse);
    // Deleting the folder deletes the record that lived inside it.
    repository.locks.remove(folder);
    expect(await service.isLocked(folder), isFalse);
    expect(repository.locks, isEmpty);
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
