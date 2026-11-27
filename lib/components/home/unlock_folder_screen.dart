import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/i18n/strings.g.dart';

/// The one password screen, for a locked folder and for any note inside one
/// (PRD FR-18).
///
/// It is rendered in place of whatever the person tried to open, so cancelling
/// simply returns to the previous view without unlocking (FR-10).
class UnlockFolderScreen extends StatefulWidget {
  const new({super.key, required this.folderPath, required this.onUnlocked});

  /// The folder, or a note inside the folder, the person tried to open.
  final String folderPath;

  /// Called with the locked folder that is now open.
  final ValueChanged<String> onUnlocked;

  @override
  State<UnlockFolderScreen> createState() => _UnlockFolderScreenState();
}

class _UnlockFolderScreenState extends State<UnlockFolderScreen> {
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
    final service = FolderLockScope.of(context);
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.home.folderLock.thisFolderIsLocked,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
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
                onSubmitted: (_) => _submit(service),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _checking
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: Text(t.common.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _checking ? null : () => _submit(service),
                    child: Text(t.home.folderLock.unlock),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Checks [password] once; repeated taps while a check runs are ignored so
  /// requests never stack (FR-19 has no limit, but this is not a retry bomb).
  Future<void> _submit(FolderLockService service) async {
    if (_checking) return;

    final password = _passwordController.text;
    if (password.isEmpty) {
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final result = await service.unlock(widget.folderPath, password);
    if (!mounted) return;

    switch (result) {
      case FolderUnlocked(:final folder):
        widget.onUnlocked(folder);
      case NothingToUnlock():
        // Nothing locks this path any more; show it rather than trap the
        // person on a password screen for an unlocked folder.
        widget.onUnlocked(widget.folderPath);
      case UnlockRefused(:final message):
        setState(() {
          _checking = false;
          _error = message;
        });
        _passwordFocus.requestFocus();
    }
  }
}
