import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
