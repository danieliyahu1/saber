import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/home/recent_note_visibility.dart';

void main() {
  group('RecentNoteVisibility.hiddenNotes', () {
    test('labels the notes under a locked folder', () {
      final hidden = RecentNoteVisibility.hiddenNotes(
        ['/a/one', '/b/two', '/three'],
        isOpen: (path) => path != '/a/one',
      );

      expect(hidden, {'/a/one'});
    });

    test('an unlocked folder turns its notes back into previews', () {
      final hidden = RecentNoteVisibility.hiddenNotes(
        ['/a/one', '/b/two'],
        isOpen: (_) => true,
      );

      expect(hidden, isEmpty);
    });

    test('every note is hidden when nothing is open', () {
      final paths = ['/a/one', '/b/two'];

      expect(
        RecentNoteVisibility.hiddenNotes(paths, isOpen: (_) => false),
        paths.toSet(),
      );
    });

    test('keeps the caller list and its order intact', () {
      final paths = ['/a/one', '/b/two', '/a/three'];
      final before = List.of(paths);

      final hidden = RecentNoteVisibility.hiddenNotes(
        paths,
        isOpen: (path) => !path.startsWith('/a'),
      );

      expect(paths, before, reason: 'the list is labelled, never filtered');
      expect(hidden, {'/a/one', '/a/three'});
    });
  });
}
