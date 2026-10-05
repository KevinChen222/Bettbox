import 'dart:convert';

import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/store.dart';
import 'package:bett_box/features/node_import/menu.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> node(String name) => {
  'name': name,
  'type': 'socks5',
  'server': 'example.com',
  'port': 1080,
};

void main() {
  test('append preserves original nodes, comments, rules and CRLF', () {
    for (final source in [
      '# keep\nproxies:\n  - {name: old, type: socks5, server: old.example, port: 1} # node\n# rules comment\nrules: [MATCH,DIRECT]\n',
      'proxies:\n- name: old\n  type: socks5\n  server: old.example\n  port: 1\nrules: [MATCH,DIRECT]',
      'proxies: [{name: old, type: socks5, server: old.example, port: 1}] # keep\nrules: [MATCH,DIRECT]\n',
      'proxies: []\nrules: [MATCH,DIRECT]\n',
      'proxies: null\nrules: [MATCH,DIRECT]\n',
      'proxies:\nrules: [MATCH,DIRECT]\n',
      'proxies: &nodes [{name: old, type: socks5, server: old.example, port: 1}]\nrules: [MATCH,DIRECT]\n',
      'proxies: &nodes\n  - {name: old, type: socks5, server: old.example, port: 1}\nrules: [MATCH,DIRECT]\n',
      '# keep\nrules: [MATCH,DIRECT]\n',
      '---\nrules: [MATCH,DIRECT]\n...\n',
      '{rules: [MATCH,DIRECT]}',
      'proxies: [{name: old, type: socks5, server: old.example, port: 1},]\nrules: [MATCH,DIRECT]\n',
      'common: &nodes [{name: old, type: socks5, server: old.example, port: 1}]\nproxies: *nodes # keep\nrules: [MATCH,DIRECT]\n',
    ]) {
      for (final content in [source, source.replaceAll('\n', '\r\n')]) {
        final before = loadYaml(content) as Map;
        final updated = appendNodesToProfile(content, [node('new')]);
        final after = loadYaml(updated) as Map;
        expect(after['proxies'], isList, reason: updated);
        expect(after['proxies'].last['name'], 'new');
        expect(
          after['proxies'].length,
          (before['proxies'] as List? ?? []).length + 1,
        );
        expect(jsonEncode(after['rules']), jsonEncode(before['rules']));
        if (before.containsKey('common')) {
          expect(jsonEncode(after['common']), jsonEncode(before['common']));
        }
        for (final comment in ['# keep', '# node', '# rules comment']) {
          if (content.contains(comment)) {
            expect(updated, contains(comment));
          }
        }
        if (content.contains('\r\n')) {
          expect(updated.replaceAll('\r\n', ''), isNot(contains('\n')));
        }
      }
    }
  });

  test(
    'name conflicts preserve imported dialer references and existing names',
    () {
      final input = [
        node('A'),
        {...node('B'), 'dialer-proxy': 'A'},
        node('A (2)'),
      ];
      final result = allocateImportedNodeNames(input, {'A', 'B'});
      expect(result.map((node) => node['name']), ['A (3)', 'B (2)', 'A (2)']);
      expect(result[1]['dialer-proxy'], 'A (3)');
      expect(input[0]['name'], 'A');
      expect(input[1]['dialer-proxy'], 'A');
    },
  );

  test(
    'external nodes survive persistence and stay out of the source profile',
    () {
      final source = <String, dynamic>{
        'proxies': [node('entry')],
        'proxy-groups': [
          {'name': 'group', 'type': 'select', 'include-all': true},
        ],
        'rules': ['MATCH,group'],
      };
      final before = jsonEncode(source);
      final chain = ProxyChain(
        id: '1',
        name: 'route',
        profileId: 'p',
        hops: const [ChainTarget.node('entry'), ChainTarget.node('exit')],
        externalNodes: [node('exit'), node('unused')],
      );
      final restored = ChainStore.decode(ChainStore.encode([chain])).single;
      final catalog = ChainCatalog(source);
      final generated = createChainProfileConfig(source, restored, catalog);
      expect(jsonEncode(source), before);
      expect(catalog.nodes.keys, ['entry']);
      expect(
        (generated['proxies'] as List).map((node) => node['name']),
        containsAll(['entry', 'exit', 'unused']),
      );
      final downstream = (generated['proxies'] as List)
          .where((node) => node['dialer-proxy'] == 'entry')
          .single;
      expect(downstream['server'], 'example.com');
      expect(generated['rules'], source['rules']);
      expect(
        generated['proxy-groups'].first['exclude-filter'],
        contains('exit'),
      );
      final duplicate = ProxyChain.fromJson({
        ...restored.toJson(),
        'id': '2',
        'name': 'copy',
      });
      final two = assembleChains(source, [restored, duplicate], catalog);
      expect(
        (two['proxies'] as List).where((node) => node['name'] == 'exit').length,
        1,
      );
      final changed = ProxyChain.fromJson({
        ...restored.toJson(),
        'externalNodes': [
          {...node('entry'), 'server': 'different.example'},
        ],
      });
      expect(
        () => assembleChains(source, [changed], catalog),
        throwsFormatException,
      );
      final cycle = ProxyChain.fromJson({
        ...restored.toJson(),
        'entryGroups': ['group'],
        'hops': [
          {'kind': 'node', 'id': 'exit'},
          {'kind': 'node', 'id': 'entry'},
        ],
        'externalNodes': [
          {...node('exit'), 'dialer-proxy': 'group'},
        ],
      });
      expect(
        () => assembleChains(source, [cycle], catalog),
        throwsFormatException,
      );
    },
  );

  testWidgets('node menu offers both choices and dismisses on blank space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    NodeImportMethod? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.bottomLeft,
              child: FloatingActionButton.extended(
                onPressed: () async =>
                    selection = await showNodeImportMenu(context),
                label: const Text('Add nodes'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add nodes'));
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsOneWidget);
    expect(find.text('Subscription URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(370, 100));
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsNothing);
    expect(selection, isNull);
    await tester.tap(find.text('Add nodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription URL'));
    await tester.pumpAndSettle();
    expect(selection, NodeImportMethod.subscription);
  });
}
