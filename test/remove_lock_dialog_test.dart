import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/lock_badge.dart';
import 'package:saber/components/home/lock_folder_button.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

/// The Remove lock menu entry and dialog, verbatim against PRD FR-4, FR-5,
/// FR-6 and FR-43…FR-46.
void main() {
  const folder = '/notes';
  const password = 'hunter2';

  late MemoryFolderLockRepository repository;
  late FolderLockService service;

  setUp(() {
    repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() => service.dispose());

  Widget app() => FolderLockScope(
    service: service,
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            LockBadge(folderPath: folder),
            LockFolderButton(folderPath: folder),
          ],
        ),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove lock'));
    await tester.pumpAndSettle();
  }

  testWidgets('a locked folder offers Remove lock with the PRD copy', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text('Remove lock'), findsWidgets);
    expect(
      find.text('Enter the password to remove the lock from this folder.'),
      findsOneWidget,
    );
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Show password'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('an empty field does nothing at all', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Remove lock'), findsWidgets, reason: 'dialog stays');
    expect(find.text('Wrong password.'), findsNothing);
    expect(await service.isLocked(folder), isTrue);
  });

  testWidgets('a wrong password is refused and nothing changes', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'not it');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong password.'), findsOneWidget);
    expect(find.text('Remove lock'), findsWidgets, reason: 'dialog stays');
    expect(await service.isLocked(folder), isTrue);
    expect(repository.locks.containsKey(folder), isTrue);
  });

  testWidgets('cancel changes nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsNothing, reason: 'dialog closed');
    expect(await service.isLocked(folder), isTrue);
    expect(find.byTooltip('Locked'), findsOneWidget);
  });

  testWidgets('Show password reveals only while toggled', (tester) async {
    await openDialog(tester);
    EditableText field() => tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byType(EditableText),
      ),
    );

    expect(field().obscureText, isTrue);
    await tester.tap(find.text('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    await tester.tap(find.text('Show password'));
    await tester.pump();
    expect(field().obscureText, isTrue);
  });

  testWidgets('the right password removes the lock and the badge', (
    tester,
  ) async {
    await openDialog(tester);
    expect(find.byTooltip('Locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsNothing, reason: 'dialog closed');
    expect(await service.isLocked(folder), isFalse);
    expect(repository.locks, isEmpty);
    expect(
      find.byTooltip('Locked'),
      findsNothing,
      reason: 'no manual refresh needed',
    );
    expect(find.byTooltip('Lock folder'), findsOneWidget);
  });

  testWidgets('an unreadable record refuses with Wrong password. (NFR-8)', (
    tester,
  ) async {
    repository.corrupt.add(folder);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong password.'), findsOneWidget);
    expect(await service.isLocked(folder), isTrue);
  });

  testWidgets('a failed delete keeps the lock and explains itself', (
    tester,
  ) async {
    repository.failDeletes = true;
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Could not remove the lock.'), findsOneWidget);
    expect(await service.isLocked(folder), isTrue);
  });
}
