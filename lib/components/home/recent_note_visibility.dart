/// Which recent notes must hide their contents (PRD FR-20, FR-21).
///
/// The rule is a label, not a filter: the list keeps its order and selection,
/// and each hidden entry becomes a title with a lock mark instead of a preview.
abstract final class RecentNoteVisibility {
  /// The paths among [paths] whose contents may not be shown right now.
  ///
  /// [isOpen] answers "may this note's contents be shown?", which the service
  /// resolves through the nearest locked ancestor and the session set.
  static Set<String> hiddenNotes(
    Iterable<String> paths, {
    required bool Function(String path) isOpen,
  }) {
    return {
      for (final path in paths)
        if (!isOpen(path)) path,
    };
  }
}
