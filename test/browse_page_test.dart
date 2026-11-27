import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/pages/home/browse.dart';

import 'utils/folder_lock_fakes.dart';
import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('BrowsePage', () {
    FlavorConfig.setup();
    setupMockPathProvider();

    setUp(() async {
      await FileManager.init(shouldWatchRootDirectory: false);
    });

    for (final depth in [0, 1, 4]) {
      final path = switch (depth) {
        0 => null,
        1 => '/folder1',
        _ => '/path/to/a/deep folder',
      };
      group('at $depth depth:', () {
        testGoldens('Empty', (tester) async {
          await tester.pumpWidget(_BrowseApp(path: path, children: null));
          // Let the folder-lock gate resolve so the loading below sees the
          // widgets that are actually on screen.
          await tester.pumpAndSettle();
          await tester.loadAssets();
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/browse_page_empty_$depth.png'),
          );
        });

        testGoldens('Non-empty', (tester) async {
          final children = DirectoryChildren(
            const ['subfolder1', 'subfolder2'],
            const ['file1', 'file2', 'file3'],
          );

          await tester.pumpWidget(_BrowseApp(path: path, children: children));
          await tester.pumpAndSettle();
          await tester.loadAssets();
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/browse_page_non_empty_$depth.png'),
          );
        });
      });
    }
  });
}

class _BrowseApp extends StatelessWidget {
  const new({required this.path, required this.children});

  final String? path;
  final DirectoryChildren? children;

  static final _folderLockService = FolderLockService(
    repository: MemoryFolderLockRepository(),
    hasher: EchoPasswordHasher(),
  );

  @override
  Widget build(BuildContext context) {
    BrowsePage.overrideChildren = children;
    return FolderLockScope(
      service: _folderLockService,
      child: ScreenshotApp.withConditionalTitlebar(
        device: GoldenSmallDevices.androidPhone.device,
        title: 'Saber',
        theme: SaberTheme.createThemeFromSeed(Colors.yellow, .light, .android),
        home: BrowsePage(path: path),
      ),
    );
  }
}
