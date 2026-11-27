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

void main() {
  group('Browse page folder gate', () {
    late MemoryFolderLockRepository repository;
    late FolderLockService service;

    setUp(() {
      FlavorConfig.setup();
      setupMockPathProvider();
      stows.sentryConsent.value = .granted;
      FileManager.init(shouldWatchRootDirectory: false);

      BrowsePage.overrideChildren = DirectoryChildren(
        ['subfolder'],
        ['secret note'],
      );

      repository = MemoryFolderLockRepository();
      repository.locks['/locked'] = lockAccepting('hunter2');
      service = FolderLockService(
        repository: repository,
        hasher: EchoPasswordHasher(),
      );
    });

    tearDown(() {
      service.dispose();
      BrowsePage.overrideChildren = null;
    });

    testWidgets('a locked folder never builds its contents', (tester) async {
      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsOneWidget);
      expect(find.text('secret note'), findsNothing);
      expect(find.text('subfolder'), findsNothing);
    });

    testWidgets('a wrong password leaves the contents unbuilt', (tester) async {
      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('secret note'), findsNothing);
    });

    testWidgets('the right password shows the contents in the same view', (
      tester,
    ) async {
      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('secret note'), findsOneWidget);
      expect(find.text('subfolder'), findsOneWidget);
    });

    testWidgets('a folder with no lock shows its contents straight away', (
      tester,
    ) async {
      await tester.pumpWidget(_app(service, path: '/open'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('secret note'), findsOneWidget);
    });

    testWidgets('opening by deep link goes through the same gate', (
      tester,
    ) async {
      repository.locks['/locked/nested'] = lockAccepting('another');

      await tester.pumpWidget(_app(service, path: '/locked/nested'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsOneWidget);
      expect(find.text('secret note'), findsNothing);
    });

    testWidgets('two nested locks ask for each password in turn', (
      tester,
    ) async {
      repository.locks['/locked'] = lockAccepting('outer');
      repository.locks['/locked/subfolder'] = lockAccepting('inner');

      await tester.pumpWidget(_app(service));
      await tester.pumpAndSettle();
      expect(find.text('This folder is locked.'), findsOneWidget);

      // The outer password opens the outer folder only.
      await tester.enterText(find.byType(TextField), 'outer');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('secret note'), findsOneWidget);

      // The inner folder has its own password.
      await tester.tap(find.text('subfolder'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is locked.'), findsOneWidget);
      expect(find.text('secret note'), findsNothing);

      await tester.enterText(find.byType(TextField), 'outer');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('secret note'), findsNothing);

      await tester.enterText(find.byType(TextField), 'inner');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('secret note'), findsOneWidget);
    });
  });
}

Widget _app(FolderLockService service, {String path = '/locked'}) {
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
