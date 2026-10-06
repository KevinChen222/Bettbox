import 'dart:convert';

import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/store.dart';
import 'package:bett_box/features/node_import/menu.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:bett_box/features/node_import/view.dart';
import 'package:bett_box/models/profile.dart';
import 'package:bett_box/l10n/l10n.dart';
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
  test('prepend preserves original nodes, comments, rules and CRLF', () {
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
        final updated = prependNodesToProfile(content, [node('new')]);
        final after = loadYaml(updated) as Map;
        expect(after['proxies'], isList, reason: updated);
        expect(after['proxies'].first['name'], 'new');
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

  test('providers preserve block indentation, anchors, comments and CRLF', () {
    for (final source in [
      '# keep\nrules: [MATCH,DIRECT]\n',
      '---\nrules: [MATCH,DIRECT]\n...\n',
      'proxy-providers:\nrules: [MATCH,DIRECT]\n',
      'proxy-providers: null\nrules: [MATCH,DIRECT]\n',
      'proxy-providers: {}\nrules: [MATCH,DIRECT]\n',
      'proxy-providers:\n  old:\n    type: http\n    url: https://old.example/sub # keep\n    interval: 123\nrules: [MATCH,DIRECT]\n',
      'proxy-providers:\n    old: {type: inline, payload: []} # keep\nrules: [MATCH,DIRECT]\n',
      'proxy-providers: &providers\n  old: {type: inline, payload: []}\nrules: [MATCH,DIRECT]\n',
      'common: &providers {old: {type: inline, payload: []}}\nproxy-providers: *providers # keep\nrules: [MATCH,DIRECT]\n',
      '{proxy-providers: {old: {type: inline, payload: []}}, rules: [MATCH,DIRECT]}',
      'proxy-providers: {old: {type: inline, payload: []}}\nrules: [MATCH,DIRECT]\n',
    ]) {
      for (final content in [source, source.replaceAll('\n', '\r\n')]) {
        final before = loadYaml(content) as Map;
        final provider = subscriptionProvider(
          '新增: 订阅',
          'https://example.com/xxx?x=1&flag=clash',
          before['proxy-providers'] as Map? ?? {},
        );
        final updated = addProviderToProfile(content, '新增: 订阅', provider);
        final after = loadYaml(updated) as Map;
        expect(
          jsonEncode(after['proxy-providers']['新增: 订阅']),
          jsonEncode(provider),
          reason: updated,
        );
        expect(after['proxy-providers']['新增: 订阅']['interval'], 86400);
        expect(
          after['proxy-providers']['新增: 订阅']['health-check']['interval'],
          600,
        );
        expect(
          after['proxy-providers']['新增: 订阅'].containsKey('override'),
          false,
        );
        expect(
          jsonEncode(after['proxy-providers']['old']),
          jsonEncode((before['proxy-providers'] as Map? ?? {})['old']),
        );
        expect(jsonEncode(after['rules']), jsonEncode(before['rules']));
        if (content.contains('# keep')) expect(updated, contains('# keep'));
        if (before.containsKey('common')) {
          expect(jsonEncode(after['common']), jsonEncode(before['common']));
        }
        if (content.contains('\r\n')) {
          expect(updated.replaceAll('\r\n', ''), isNot(contains('\n')));
        }
      }
    }
  });

  test(
    'subscription names and provider cache paths do not overwrite existing entries',
    () {
      expect(
        subscriptionNameFromHeaders({
          'profile-title': ['base64:${base64Encode(utf8.encode('订阅名'))}'],
        }),
        '订阅名',
      );
      expect(
        subscriptionNameFromHeaders({
          'content-disposition': [
            "attachment; filename*=UTF-8''%E8%AE%A2%E9%98%85.yaml",
          ],
        }),
        '订阅.yaml',
      );
      expect(allocateSubscriptionName('', {'新添加1', '新添加2'}), '新添加3');
      expect(allocateSubscriptionName('custom', {'custom'}), 'custom (2)');
      final provider = subscriptionProvider('a/b', 'https://example.com', {
        'old': {'path': './proxies/a_b.yaml'},
      });
      expect(provider['path'], './proxies/a_b (2).yaml');
    },
  );

  test(
    'provider deletion cleans use references and retains populated groups',
    () {
      const content = '''
proxy-providers: {a: {type: inline, payload: []}, b: {type: inline, payload: []}}
proxy-groups:
  - {name: empty, type: select, use: [a]}
  - {name: populated, type: select, use: [a, b], proxies: [DIRECT]}
rules: [MATCH,empty] # keep
''';
      final updated = removeProvidersFromProfile(content, {'a'});
      final config = loadYaml(updated) as Map;
      expect(config['proxy-providers'].keys, ['b']);
      expect(config['proxy-groups'][0]['proxies'], ['DIRECT']);
      expect(config['proxy-groups'][1]['use'], ['b']);
      expect(updated, contains('rules: [MATCH,empty] # keep'));
    },
  );

  test('profile additions survive refreshed subscriptions and backup JSON', () {
    final manual = [
      node('manual'),
      {...node('exit'), 'dialer-proxy': 'manual'},
    ];
    final providers = {
      'subscription': subscriptionProvider(
        'subscription',
        'https://example.com',
        {},
      ),
    };
    final profile = Profile.normal(
      url: 'https://main.example',
    ).copyWith(addedNodes: manual, addedProviders: providers);
    final restored = Profile.fromJson(
      jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
    );
    expect(restored.addedNodes, manual);
    expect(restored.addedProviders, providers);
    final fresh =
        'proxies: ${jsonEncode([node('manual')])}\nproxy-providers: {subscription: {type: inline, payload: []}}\nrules: [MATCH,DIRECT]\n';
    final merged = mergeProfileAdditions(
      fresh,
      restored.addedNodes,
      restored.addedProviders,
    );
    final config = loadYaml(merged.content) as Map;
    expect(config['proxies'].map((node) => node['name']), [
      'manual (2)',
      'exit',
      'manual',
    ]);
    expect(config['proxies'][1]['dialer-proxy'], 'manual (2)');
    expect(config['proxy-providers'].keys, [
      'subscription',
      'subscription (2)',
    ]);
    final again = mergeProfileAdditions(fresh, merged.nodes, merged.providers);
    expect(jsonEncode(loadYaml(again.content)), jsonEncode(config));
    final deleted = mergeProfileAdditions(fresh, [], {});
    expect(deleted.content, fresh);
  });

  testWidgets('provider subscription dialog has spaced name and URL fields', (
    tester,
  ) async {
    await AppLocalizations.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSubscriptionImport(context, provider: true),
              child: const Text('provider'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('provider'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    final fields = find.byType(TextField);
    expect(
      tester.getTopLeft(fields.last).dy - tester.getBottomLeft(fields.first).dy,
      greaterThanOrEqualTo(24),
    );
    expect(tester.takeException(), isNull);
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
        externalSubscriptions: const {
          'sub': ['exit', 'unused'],
        },
      );
      final restored = ChainStore.decode(ChainStore.encode([chain])).single;
      expect(restored.externalSubscriptions, {
        'sub': ['exit', 'unused'],
      });
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
