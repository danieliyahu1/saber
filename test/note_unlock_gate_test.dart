import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/note_unlock_gate.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';

import 'utils/folder_lock_fakes.dart';

void main() {
  group('NoteUnlockGate', () {
    const notePath = '/locked/diary.sbn2';

    late MemoryFolderLockRepository repository;
    late FolderLockService service;
    late int editorBuilds;

    setUp(() {
      repository = MemoryFolderLockRepository();
      repository.locks['/locked'] = lockAccepting('hunter2');
      service = FolderLockService(
        repository: repository,
        hasher: EchoPasswordHasher(),
      );
      editorBuilds = 0;
    });

    tearDown(() => service.dispose());

    Widget gate(String? path) => MaterialApp(
      home: FolderLockScope(
        service: service,
        child: NoteUnlockGate(
          notePath: path,
          builder: (context) {
            editorBuilds++;
            return Text('editor for $path');
          },
        ),
      ),
    );

    testWidgets('the editor is never built while the folder is locked', (
      tester,
    ) async {
      await tester.pumpWidget(gate(notePath));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsOneWidget);
      expect(editorBuilds, 0);
      expect(find.textContaining('editor for'), findsNothing);
    });

    testWidgets('a wrong password still builds no editor', (tester) async {
      await tester.pumpWidget(gate(notePath));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong password.'), findsOneWidget);
      expect(editorBuilds, 0);
    });

    testWidgets('the right password opens the tapped note, not its folder', (
      tester,
    ) async {
      await tester.pumpWidget(gate(notePath));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('editor for $notePath'), findsOneWidget);
      expect(editorBuilds, greaterThan(0));
      expect(await service.isOpen('/locked'), isTrue);
    });

    testWidgets('a note with no lock opens straight away', (tester) async {
      await tester.pumpWidget(gate('/open/note.sbn2'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('editor for /open/note.sbn2'), findsOneWidget);
    });

    testWidgets('no note path means there is nothing to gate', (tester) async {
      await tester.pumpWidget(gate(null));
      await tester.pumpAndSettle();

      expect(find.text('This folder is locked.'), findsNothing);
      expect(find.text('editor for null'), findsOneWidget);
    });
  });
}
