import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/i18n/strings.g.dart';

/// Chooses a folder's password (PRD FR-35…FR-42).
///
/// The copy is the PRD's, verbatim. The warning under the field changes with
/// the device, because whether a forgotten password can be undone does
/// (FR-39, FR-40, NFR-3).
class LockFolderDialog extends StatefulWidget {
  const new({super.key, required this.folderPath, required this.isComputer});

  /// The folder being locked, not a note inside it.
  final String folderPath;

  /// True where the lock can be removed by hand.
  final bool isComputer;

  @override
  State<LockFolderDialog> createState() => _LockFolderDialogState();
}

class _LockFolderDialogState extends State<LockFolderDialog> {
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
      title: Text(t.home.folderLock.lockFolder),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.home.folderLock.lockBody),
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
            const SizedBox(height: 8),
            _Warning(t.home.folderLock.noRecovery),
            const SizedBox(height: 4),
            _Warning(
              widget.isComputer
                  ? t.home.folderLock.forgotOnComputer
                  : t.home.folderLock.forgotOnPhone,
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
          child: Text(t.home.folderLock.lock),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_checking) return;

    final service = FolderLockScope.of(context);
    setState(() {
      _checking = true;
      _error = null;
    });

    final result = await service.lock(
      widget.folderPath,
      _passwordController.text,
    );
    if (!mounted) return;

    switch (result) {
      case FolderLocked() || FolderAlreadyLocked():
        Navigator.of(context).pop();
      case LockPasswordRejected(:final message):
        _showError(message);
      case LockSaveFailed():
        // The folder is not locked when the record could not be written
        // (HLD §12); the dialog stays open so the person can retry.
        _showError(t.home.folderLock.lockFailed);
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

class _Warning extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
