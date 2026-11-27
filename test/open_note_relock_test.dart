import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_lifecycle.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/note_unlock_gate.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

/// PRD FR-29: a note that was open when the app was put away must not be
/// readable on return; its folder asks for the password instead.
void main() {
  const folder = '/notes';
  const notePath = '$folder/diary';
  const password = 'hunter2';

  late FolderLockService service;

  setUp(() {
    final repository = MemoryFolderLockRepository();
    repository.locks[folder] = lockAccepting(password);
    service = FolderLockService(
      repository: repository,
      hasher: EchoPasswordHasher(),
    );
  });

  tearDown(() {
    service.dispose();
    TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    FolderLockScope(
      service: service,
      child: FolderLockLifecycle(
        child: MaterialApp(
          home: NoteUnlockGate(
            notePath: notePath,
            builder: (context) => const Text('editor'),
          ),
        ),
      ),
    ),
  );

  Future<void> putAway(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an open note closes to its locked folder when put away', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);

    await putAway(tester, AppLifecycleState.paused);
    expect(await service.isOpen(notePath), isFalse);

    // Nothing is built while the app is away; returning must show the folder.
    await putAway(tester, AppLifecycleState.resumed);

    expect(find.text('editor'), findsNothing);
    expect(find.text('This folder is locked.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('coming back keeps the folder closed until the password', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    await putAway(tester, AppLifecycleState.hidden);
    await putAway(tester, AppLifecycleState.resumed);

    expect(find.text('editor'), findsNothing);
    expect(find.text('This folder is locked.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
  });

  testWidgets('a note that is no longer locked opens on return', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);

    // The lock was removed while the app was away.
    await service.remove(folder, password);
    await tester.pumpAndSettle();

    expect(find.text('editor'), findsOneWidget);
    expect(find.text('This folder is locked.'), findsNothing);
  });
}
