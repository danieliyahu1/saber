import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/i18n/strings.g.dart';

/// Takes a locked folder's password away (PRD FR-4, FR-5, FR-43…FR-46).
///
/// The copy is the PRD's, verbatim. Cancelling changes nothing; a wrong
/// password is refused with the same words everywhere; an empty field does
/// nothing at all (no copy is defined for it).
class RemoveLockDialog extends StatefulWidget {
  const new({super.key, required this.folderPath});

  /// The folder being unlocked, not a note inside it.
  final String folderPath;

  @override
  State<RemoveLockDialog> createState() => _RemoveLockDialogState();
}

class _RemoveLockDialogState extends State<RemoveLockDialog> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  var _showPassword = false;
  var _checking = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: Text(t.home.folderLock.removeLock),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.home.folderLock.removeLockBody),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              autofocus: true,
              enabled: !_checking,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: t.home.folderLock.password,
                errorText: _error,
                errorMaxLines: 2,
              ),
              onSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _checking
                    ? null
                    : () => setState(() => _showPassword = !_showPassword),
                child: Text(t.home.folderLock.showPassword),
              ),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        CupertinoDialogAction(
          onPressed: _checking ? null : _submit,
          child: Text(t.home.folderLock.remove),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_checking) return;

    final password = _passwordController.text;
    if (password.isEmpty) {
      // The PRD defines no empty-field copy for Remove lock: the field simply
      // stays where the person is (FR-45).
      _passwordFocus.requestFocus();
      return;
    }

    final service = FolderLockScope.of(context);
    setState(() {
      _checking = true;
      _error = null;
    });

    final result = await service.remove(widget.folderPath, password);
    if (!mounted) return;

    switch (result) {
      case LockRemoved() || RemoveNotLocked():
        Navigator.of(context).pop();
      case RemoveWrongPassword(:final message):
        _showError(message);
      case RemoveCorruptLock():
        // An unreadable record refuses every attempt the same way (NFR-8).
        _showError(FolderLockService.wrongPasswordMessage);
      case RemoveFailed():
        // The record could not be deleted, so the folder stays locked and the
        // dialog stays open for a retry (HLD §12).
        _showError(t.home.folderLock.removeFailed);
    }
  }

  void _showError(String message) {
    setState(() {
      _checking = false;
      _error = message;
    });
    _passwordFocus.requestFocus();
  }
}
