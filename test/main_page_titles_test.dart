import 'package:bett_box/l10n/l10n.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/application_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'page titles support older settings and JSON persistence including hidden titles',
    () {
      expect(AppSettingProps.fromJson({}).pageTitles, isEmpty);
      const settings = AppSettingProps(
        pageTitles: {
          'dashboard': 'home',
          'proxies': 'nodes',
          'profiles': '',
          'tools': 'settings',
        },
      );
      expect(
        AppSettingProps.fromJson(settings.toJson()).pageTitles,
        settings.pageTitles,
      );
    },
  );

  testWidgets('settings edits all four titles and can reset them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
    globalState.config = Config(themeProps: defaultThemeProps);
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, widgetRef, _) {
                ref = widgetRef;
                widgetRef.watch(appSettingProvider);
                return const MainPageTitlesItem();
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Main page titles'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      await tester.enterText(fields.at(i), i == 2 ? '' : 'custom$i');
    }
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(ref.read(appSettingProvider).pageTitles, {
      'dashboard': 'custom0',
      'proxies': 'custom1',
      'profiles': '',
      'tools': 'custom3',
    });
    await tester.tap(find.text('Main page titles'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(ref.read(appSettingProvider).pageTitles, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
