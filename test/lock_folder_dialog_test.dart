import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/lock_folder_button.dart';
import 'package:saber/components/home/lock_folder_dialog.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

void main() {
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

  group('LockFolderDialog', () {
    Widget app({bool isComputer = true}) => FolderLockScope(
      service: service,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => LockFolderDialog(
                    folderPath: '/notes',
                    isComputer: isComputer,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> open(WidgetTester tester, {bool isComputer = true}) async {
      await tester.pumpWidget(app(isComputer: isComputer));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the PRD copy verbatim (FR-35…FR-42)', (tester) async {
      await open(tester);

      expect(find.text('Lock folder'), findsOneWidget);
      expect(
        find.text(
          'Choose a password for this folder. '
          'You will need it to see what is inside.',
        ),
        findsOneWidget,
      );
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Show password'), findsOneWidget);
      expect(find.text('Lock'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.text('There is no way to recover this password.'),
        findsOneWidget,
      );
      expect(
        find.text('If you forget it, you can remove the lock by hand.'),
        findsOneWidget,
      );
    });

    testWidgets('a phone warns that a forgotten password is final (FR-39)', (
      tester,
    ) async {
      await open(tester, isComputer: false);

      expect(
        find.text('If you forget it, this folder cannot be opened again.'),
        findsOneWidget,
      );
      expect(
        find.text('If you forget it, you can remove the lock by hand.'),
        findsNothing,
      );
    });

    testWidgets('an empty password is refused without closing (FR-41)', (
      tester,
    ) async {
      await open(tester);

      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a password.'), findsOneWidget);
      expect(
        find.text(
          'Choose a password for this folder. '
          'You will need it to see what is inside.',
        ),
        findsOneWidget,
      );
      expect(repository.locks, isEmpty);
    });

    testWidgets('a short password is refused without closing (PW-2)', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();

      expect(find.text('Use at least 4 characters.'), findsOneWidget);
      expect(repository.locks, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    });

    testWidgets('a good password locks the folder and closes (FR-3)', (
      tester,
    ) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsNothing);
      expect(repository.locks['/notes'], isNotNull);
      expect(await service.isLocked('/notes'), isTrue);
    });

    testWidgets('Enter submits', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'hunter2');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(repository.locks['/notes'], isNotNull);
      expect(find.text('Password'), findsNothing);
    });

    testWidgets('cancel closes and changes nothing', (tester) async {
      await open(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsNothing);
      expect(repository.locks, isEmpty);
      expect(await service.isLocked('/notes'), isFalse);
    });

    testWidgets('show password resets when the dialog reopens (FR-9)', (
      tester,
    ) async {
      await open(tester);
      EditableText editable() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().obscureText, isTrue);

      await tester.tap(find.text('Show password'));
      await tester.pump();
      expect(editable().obscureText, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(editable().obscureText, isTrue);
    });

    testWidgets(
      'a failed write keeps the dialog open with an error (HLD §12)',
      (tester) async {
        repository.failWrites = true;
        await open(tester);

        await tester.enterText(find.byType(TextField), 'hunter2');
        await tester.tap(find.text('Lock'));
        await tester.pumpAndSettle();

        expect(find.text('Could not lock this folder.'), findsOneWidget);
        expect(find.text('Password'), findsOneWidget);
        expect(await service.isLocked('/notes'), isFalse);
      },
    );
  });

  group('LockFolderButton', () {
    Widget button() => FolderLockScope(
      service: service,
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: LockFolderButton(folderPath: '/notes')),
        ),
      ),
    );

    testWidgets('an unlocked folder offers Lock folder (FR-1, FR-33)', (
      tester,
    ) async {
      await tester.pumpWidget(button());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Lock folder'), findsOneWidget);

      await tester.tap(find.byTooltip('Lock folder'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Choose a password for this folder. '
          'You will need it to see what is inside.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a locked folder does not offer it again', (tester) async {
      repository.locks['/notes'] = lockAccepting('hunter2');

      await tester.pumpWidget(button());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Lock folder'), findsNothing);
    });

    testWidgets('the entry disappears as soon as the folder locks', (
      tester,
    ) async {
      await tester.pumpWidget(button());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Lock folder'), findsOneWidget);

      await service.lock('/notes', 'hunter2');
      await tester.pumpAndSettle();

      expect(find.byTooltip('Lock folder'), findsNothing);
    });
  });

  group('GridFolders menu', () {
    testWidgets('Lock folder sits beside rename and delete', (tester) async {
      await tester.pumpWidget(
        FolderLockScope(
          service: service,
          child: MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  GridFolders(
                    isAtRoot: false,
                    crossAxisCount: 2,
                    parentPath: '/',
                    folders: const ['notes'],
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

      await tester.longPress(find.text('notes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Lock folder'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Choose a password for this folder. '
          'You will need it to see what is inside.',
        ),
        findsOneWidget,
      );
    });
  });
}
