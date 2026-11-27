import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/folder_lock_scope.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/folder_lock/folder_lock_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/home/home.dart';

import 'utils/folder_lock_fakes.dart';

void main() {
  group('Home themes', () {
    for (final platform in TargetPlatform.values)
      for (final brightness in Brightness.values)
        testGoldens('${platform.name}_${brightness.name}', (tester) async {
          FlavorConfig.setup();
          stows.sentryConsent.value = .granted;

          final theme = SaberTheme.createThemeFromSeed(
            Colors.yellow,
            brightness,
            platform,
          );
          final folderLock = FolderLockService(
            repository: MemoryFolderLockRepository(),
            hasher: EchoPasswordHasher(),
          );
          addTearDown(folderLock.dispose);
          await tester.pumpWidget(
            ScreenshotApp.withConditionalTitlebar(
              device: GoldenScreenshotDevices.androidPhone.device,
              title: 'Saber',
              theme: theme,
              home: Theme(
                data: theme,
                child: FolderLockScope(
                  service: folderLock,
                  child: const HomePage(
                    subpage: HomePage.recentSubpage,
                    path: '',
                  ),
                ),
              ),
            ),
          );
          await tester.loadAssets();
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/home_theme_${platform.name}_${brightness.name}.png',
            ),
          );
        });
  });
}
