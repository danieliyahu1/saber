import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/lock_badge.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

void main() {
  group('LockBadge', () {
    late MemoryFolderLockRepository repository;
    late FolderLockService service;

    setUp(() {
      repository = MemoryFolderLockRepository();
      service = FolderLockService(
        repository: repository,
        hasher: EchoPasswordHasher(),
      );
    });

    tearDown(() => service.dispose());

    Widget badge(String folderPath) => MaterialApp(
      home: FolderLockScope(
        service: service,
        child: Scaffold(
          body: Center(child: LockBadge(folderPath: folderPath)),
        ),
      ),
    );

    testWidgets(
      'a locked folder wears the mark and its tooltip (FR-6, FR-48)',
      (tester) async {
        repository.locks['/notes'] = lockAccepting('hunter2');

        await tester.pumpWidget(badge('/notes'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Locked'), findsOneWidget);
        expect(find.byIcon(Icons.lock), findsOneWidget);
      },
    );

    testWidgets('an unlocked folder wears nothing', (tester) async {
      await tester.pumpWidget(badge('/notes'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Locked'), findsNothing);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('the mark is readable by a screen reader (NFR-9)', (
      tester,
    ) async {
      repository.locks['/notes'] = lockAccepting('hunter2');
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(badge('/notes'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byIcon(Icons.lock)).label,
        contains('Locked'),
      );

      semantics.dispose();
    });

    testWidgets('locking a folder updates the mark without a refresh', (
      tester,
    ) async {
      await tester.pumpWidget(badge('/notes'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Locked'), findsNothing);

      await service.lock('/notes', 'hunter2');
      await tester.pumpAndSettle();

      expect(find.byTooltip('Locked'), findsOneWidget);
    });

    testWidgets('folder listings mark only the locked folder', (tester) async {
      repository.locks['/parent/locked folder'] = lockAccepting('hunter2');

      await tester.pumpWidget(
        MaterialApp(
          home: FolderLockScope(
            service: service,
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  GridFolders(
                    isAtRoot: false,
                    crossAxisCount: 2,
                    parentPath: '/parent',
                    folders: const ['locked folder', 'plain folder'],
                    onTap: (_) {},
                    createFolder: (_) {},
                    doesFolderExist: (_) => false,
                    renameFolder: (_, _) async {},
                    isFolderEmpty: (_) async => true,
                    deleteFolder: (_) async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Locked'), findsOneWidget);
    });

    testWidgets('a long folder name does not push the mark out of the card', (
      tester,
    ) async {
      const longName =
          'a very long folder name that keeps going and going and going';
      repository.locks['/parent/$longName'] = lockAccepting('hunter2');

      await tester.pumpWidget(
        MaterialApp(
          home: FolderLockScope(
            service: service,
            child: Scaffold(
              body: CustomScrollView(
                slivers: [
                  GridFolders(
                    isAtRoot: false,
                    crossAxisCount: 3,
                    parentPath: '/parent',
                    folders: const [longName],
                    onTap: (_) {},
                    createFolder: (_) {},
                    doesFolderExist: (_) => false,
                    renameFolder: (_, _) async {},
                    isFolderEmpty: (_) async => true,
                    deleteFolder: (_) async {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find.ancestor(of: find.text(longName), matching: find.byType(Card)),
      );
      final mark = tester.getRect(find.byTooltip('Locked'));

      expect(mark.right, lessThanOrEqualTo(card.right));
      expect(mark.top, greaterThanOrEqualTo(card.top));
      expect(mark.bottom, lessThanOrEqualTo(card.bottom));
    });
  });
}
