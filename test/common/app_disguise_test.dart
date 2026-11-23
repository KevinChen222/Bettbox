import 'dart:io';

import 'package:bett_box/common/app_disguise.dart';
import 'package:bett_box/common/app_localizations.dart';
import 'package:bett_box/common/constant.dart';
import 'package:bett_box/common/fixed.dart';
import 'package:bett_box/l10n/l10n.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/app_disguise.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

void main() {
  test('effectiveAppName trims custom name and falls back to default', () {
    expect(effectiveAppName(null), appName);
    expect(effectiveAppName('   '), appName);
    expect(effectiveAppName('  日常笔记  '), '日常笔记');
  });

  test('AppDisguisePreset resolves known presets and defaults safely', () {
    expect(AppDisguisePreset.fromId('notes'), AppDisguisePreset.notes);
    expect(
      AppDisguisePreset.fromId('calculator'),
      AppDisguisePreset.calculator,
    );
    expect(AppDisguisePreset.fromId('toolbox'), AppDisguisePreset.toolbox);
    expect(AppDisguisePreset.fromId('unknown'), AppDisguisePreset.defaultPreset);
    expect(AppDisguisePreset.fromId(null), AppDisguisePreset.defaultPreset);
  });

  test('encodeSquareAppIconPng crops rectangular images to 256x256 PNG', () {
    final source = img.Image(width: 400, height: 200);
    img.fill(source, color: img.ColorRgb8(20, 140, 120));
    final inputBytes = Uint8List.fromList(img.encodePng(source));

    final encoded = encodeSquareAppIconPng(inputBytes);
    final decoded = img.decodePng(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);
  });

  test('saveCustomAppIconFromFile writes icon and replaces previous icon', () async {
    final tempDir = await Directory.systemTemp.createTemp('app_disguise_test');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sample = img.Image(width: 120, height: 80);
    img.fill(sample, color: img.ColorRgb8(240, 160, 40));
    final srcPath = p.join(tempDir.path, 'input.png');
    await File(srcPath).writeAsBytes(img.encodePng(sample));

    final firstPath = await saveCustomAppIconFromFile(
      srcPath,
      targetDirPath: tempDir.path,
    );
    expect(File(firstPath).existsSync(), isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    final secondPath = await saveCustomAppIconFromFile(
      srcPath,
      previousPath: firstPath,
      targetDirPath: tempDir.path,
    );
    expect(File(secondPath).existsSync(), isTrue);
    expect(File(firstPath).existsSync(), isFalse);
  });

  testWidgets(
    'editing custom app name inside a nested navigator closes dialog and saves',
    (tester) async {
      globalState.appState = AppState(
        brightness: Brightness.light,
        version: 0,
        viewSize: const Size(1024, 768),
        requests: FixedList(maxLength),
        logs: FixedList(maxLogLength),
        traffics: FixedList(30),
        totalTraffic: Traffic(),
        systemUiOverlayStyle: const SystemUiOverlayStyle(),
      );
      globalState.config = Config(
        themeProps: defaultThemeProps,
        networkProps: defaultNetworkProps,
      );
      final nestedNavKey = GlobalKey<NavigatorState>();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                navigatorKey: globalState.navigatorKey,
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                home: Scaffold(
                  body: Navigator(
                    key: nestedNavKey,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('PreviousPage')),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      nestedNavKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: AppDisguiseView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDisguiseView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('disguise-name-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wire');
      await tester.tap(find.text(appLocalizations.confirm));
      await tester.pumpAndSettle();

      // Dialog must be dismissed, AppDisguiseView must remain on screen, and name must be saved.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AppDisguiseView), findsOneWidget);
      expect(container.read(appSettingProvider).customAppName, 'wire');
      expect(find.text('wire'), findsAtLeastNWidgets(1));
      expect(find.byKey(const ValueKey('disguise-reset-button')), findsOneWidget);

      // Tapping reset restores default name and hides reset button.
      await tester.tap(find.byKey(const ValueKey('disguise-reset-button')));
      await tester.pumpAndSettle();
      expect(container.read(appSettingProvider).customAppName, isNull);
      expect(find.byKey(const ValueKey('disguise-reset-button')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    },
  );
}
