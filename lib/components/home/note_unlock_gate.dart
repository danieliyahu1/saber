import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/home/unlock_folder_screen.dart';

/// Puts the password screen in front of a note, wherever the note is opened
/// from.
///
/// Wrapping [builder] means the editor is not constructed until the note's
/// folder is open, so no part of a locked note is ever built, let alone shown
/// (PRD FR-13, FR-17). The `/edit` route covers deep links, shares and
/// restored navigation; the home preview card covers recent notes and any
/// listing (PRD FR-1…FR-3 of the HLD's access section).
class NoteUnlockGate extends StatefulWidget {
  const new({super.key, required this.notePath, required this.builder});

  /// The note the person asked for. Null means no note was named (an empty
  /// editor route), which is not something a folder lock can protect.
  final String? notePath;

  /// Builds the editor for [notePath]. Only called once it is allowed.
  final WidgetBuilder builder;

  @override
  State<NoteUnlockGate> createState() => _NoteUnlockGateState();
}

class _NoteUnlockGateState extends State<NoteUnlockGate> {
  /// Null while the answer is unknown, so the editor is never built early.
  bool? _mayBeShown;

  var _check = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkLock();
  }

  Future<void> _checkLock() async {
    final notePath = widget.notePath;
    if (notePath == null) {
      if (_mayBeShown != true) setState(() => _mayBeShown = true);
      return;
    }

    final check = ++_check;
    final mayBeShown = await FolderLockScope.of(context).isOpen(notePath);
    if (!mounted || check != _check) return;
    if (_mayBeShown != mayBeShown) {
      setState(() => _mayBeShown = mayBeShown);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mayBeShown == true) return widget.builder(context);

    if (_mayBeShown == false) {
      return Scaffold(
        body: UnlockFolderScreen(
          folderPath: widget.notePath!,
          onUnlocked: (_) => _checkLock(),
        ),
      );
    }

    return const Scaffold(body: SizedBox.shrink());
  }
}
