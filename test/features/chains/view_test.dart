import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'deletion offers only imported nodes, confirms and removes dependent hops',
    (tester) async {
      final source = <String, dynamic>{
        'proxies': [
          {
            'name': 'source',
            'type': 'socks5',
            'server': 'source.example',
            'port': 1080,
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ChainEditorView(
            chain: ProxyChain(
              id: '1',
              name: 'test',
              profileId: 'p',
              hops: const [
                ChainTarget.node('source'),
                ChainTarget.node('imported1'),
              ],
              externalNodes: [
                for (final name in ['imported1', 'imported2'])
                  {
                    'name': name,
                    'type': 'socks5',
                    'server': 'external.example',
                    'port': 1080,
                  },
              ],
            ),
            profileLabel: 'profile',
            source: source,
            catalog: ChainCatalog(source),
          ),
        ),
      );
      final button = find.widgetWithText(OutlinedButton, 'Delete added nodes');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'source'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'imported1'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'imported2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 nodes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'imported1'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'imported2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('source').first);
      expect(find.text('imported1'), findsNothing);
      expect(find.text('source'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editor previews direction and permits mobile hop reordering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = <String, dynamic>{
      'proxies': [
        {
          'name': 'First',
          'type': 'socks5',
          'server': 'first.example.com',
          'port': 1080,
        },
        {
          'name': 'Last',
          'type': 'socks5',
          'server': 'last.example.com',
          'port': 1080,
        },
      ],
      'proxy-groups': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: ChainEditorView(
          chain: const ProxyChain(
            id: '1',
            name: 'Test route',
            profileId: '1',
            hops: [ChainTarget.node('First'), ChainTarget.node('Last')],
          ),
          profileLabel: 'Profile',
          source: source,
          catalog: ChainCatalog(source),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final addHop = find.widgetWithText(OutlinedButton, 'Add hop');
    final paths = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(paths);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(paths).dy - tester.getBottomLeft(addHop).dy,
      greaterThanOrEqualTo(16),
    );
    await tester.ensureVisible(find.byTooltip('Move down').first);
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Last → First'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Last → First'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Remove').first);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(addHop);
    await tester.tap(addHop);
    await tester.pumpAndSettle();
    final external = find.text('Add external nodes');
    final local = find.text('Local / custom HTTP or SOCKS endpoint');
    expect(
      tester.getTopLeft(external).dy,
      lessThan(tester.getTopLeft(local).dy),
    );
    await tester.tap(external);
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsOneWidget);
    expect(find.text('Subscription URL'), findsOneWidget);
    await tester.tapAt(const Offset(380, 100));
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsNothing);
    expect(external, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
