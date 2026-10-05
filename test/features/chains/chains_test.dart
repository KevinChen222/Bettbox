import 'dart:convert';
import 'dart:io';

import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> node(String name, {String server = 'example.com'}) => {
  'name': name,
  'type': 'socks5',
  'server': server,
  'port': 1080,
  'udp': true,
  'tls-options': {'sni': 'example.com'},
};

Map<String, dynamic> source() => {
  'proxies': [node('A'), node('B')],
  'proxy-groups': [
    {
      'name': '入口',
      'type': 'select',
      'proxies': ['A', 'B', 'DIRECT'],
    },
    {
      'name': 'Smart',
      'type': 'smart',
      'proxies': ['A', 'B'],
      'policy-priority': 'B:1.5',
    },
  ],
  'rules': ['MATCH,入口'],
  'dns': {'enable': true},
};

ProxyChain chain({
  String id = '1',
  String name = 'route',
  List<ChainTarget>? hops,
  List<String> entries = const ['入口'],
  int limit = 64,
}) => ProxyChain(
  id: id,
  name: name,
  profileId: 'profile',
  hops: hops ?? const [ChainTarget.node('A'), ChainTarget.node('B')],
  entryGroups: entries,
  branchLimit: limit,
);

void main() {
  test('inline case flags preserve names and negative-lookahead filtering', () {
    final names = ['🇭🇰 hk Gomami 12.9', '🇺🇸 US zgo', 'DIRECT', 'direct-v4'];
    final config = <String, dynamic>{
      'proxies': names.map(node).toList(),
      'proxy-groups': [
        {
          'name': '🐸 手动切换',
          'type': 'select',
          'include-all': true,
          'filter': '(?i)^(?!.*(direct))',
        },
        {
          'name': '🇭🇰 香港节点',
          'type': 'select',
          'include-all': true,
          'filter': '(?i)HK`(?i)US',
          'exclude-filter': '(?i)ZGO',
        },
      ],
    };
    final catalog = ChainCatalog(config);
    expect(catalog.groups['🐸 手动切换']!.map((hop) => hop.id), names.take(2));
    expect(catalog.groups['🇭🇰 香港节点']!.single.id, names.first);
    expect(catalog.nodes.keys, names);
  });

  test(
    'filters match core semantics for explicit nodes and excluded group types',
    () {
      final config = source();
      config['proxy-groups'].add({
        'name': 'mixed',
        'type': 'select',
        'proxies': ['A', 'Smart'],
        'use': ['sub'],
        'filter': '^HK`^JP',
        'exclude-type': 'SMART',
      });
      final catalog = ChainCatalog(
        config,
        providers: {
          'sub': [node('HK'), node('JP'), node('US')],
        },
      );
      final members = catalog.groups['mixed']!;
      expect(members.map((target) => catalog.nodes[target.id]!['name']), [
        'A',
        'HK',
        'JP',
      ]);
    },
  );
  test(
    'new profile and YAML export route through the actual allocated chain name',
    () {
      final config = source();
      final created = createChainProfileConfig(
        config,
        chain(name: '入口'),
        ChainCatalog(config),
      );
      expect(created['rules'], ['MATCH,入口 (2)']);
      expect(created['mode'], 'rule');
      expect(config['rules'], ['MATCH,入口']);
    },
  );
  test('three-hop direction, terminal selector and source isolation', () {
    final config = source();
    final before = jsonEncode(config);
    final catalog = ChainCatalog(config);
    final route = chain(
      hops: const [
        ChainTarget.node('A'),
        ChainTarget.node('B'),
        ChainTarget.localEndpoint({
          'name': 'exit',
          'type': 'http',
          'server': '127.0.0.1',
          'port': 8080,
        }),
      ],
    );
    final result = catalog.compile(route, {});
    expect(result.isValid, isTrue);
    final names = result.paths.single.generatedNames;
    expect(result.generatedProxies[names[0]]!['dialer-proxy'], isNull);
    expect(result.generatedProxies[names[1]]!['dialer-proxy'], names[0]);
    expect(result.generatedProxies[names[2]]!['dialer-proxy'], names[1]);
    expect(result.generatedGroups.single.proxies, [names.last]);
    final assembled = assembleChains(config, [route], catalog);
    expect((assembled['proxy-groups'] as List).first['proxies'], [
      'A',
      'B',
      'DIRECT',
      'route',
    ]);
    expect(assembled['rules'], config['rules']);
    expect(
      (assembled['proxy-groups'] as List)[1],
      (config['proxy-groups'] as List)[1],
    );
    ((assembled['proxies'] as List).last as Map)['server'] = 'changed';
    expect(jsonEncode(config), before);
  });

  test('groups expand all combinations, cap branches and detect cycles', () {
    final config = source();
    final catalog = ChainCatalog(config);
    final route = chain(
      hops: const [ChainTarget.group('入口'), ChainTarget.group('Smart')],
    );
    expect(catalog.compile(route, {}).paths, hasLength(4));
    final limited = chain(hops: route.hops, limit: 3);
    expect(
      catalog.compile(limited, {}).diagnostics.single.code,
      'branch-limit-exceeded',
    );
    (config['proxy-groups'] as List).add({
      'name': 'loop',
      'type': 'select',
      'proxies': ['loop'],
    });
    final cycle = ChainCatalog(
      config,
    ).compile(chain(hops: const [ChainTarget.group('loop')]), {});
    expect(cycle.isValid, isFalse);
    expect(cycle.diagnostics.single.code, 'group-cycle');
  });

  test(
    'collisions allocate names without changing original rules or nodes',
    () {
      final config = source();
      final result = assembleChains(config, [
        chain(name: '入口'),
        chain(id: '2', name: '入口'),
      ], ChainCatalog(config));
      final groups = result['proxy-groups'] as List;
      expect(groups.map((g) => g['name']), ['入口', 'Smart', '入口 (2)', '入口 (3)']);
      expect(groups.first['proxies'], ['A', 'B', 'DIRECT', '入口 (2)', '入口 (3)']);
      expect(result['rules'], ['MATCH,入口']);
      expect((result['proxies'] as List).take(2), config['proxies']);
      expect(assembleChains(config, [], ChainCatalog(config)), same(config));
    },
  );

  test(
    'subscription refresh resolves current node and rejects removed references',
    () {
      final refreshed = source();
      refreshed['proxies'][0] = node('A', server: 'new.example.com');
      final catalog = ChainCatalog(refreshed);
      final result = catalog.compile(chain(), {});
      expect(result.generatedProxies.values.first['server'], 'new.example.com');
      refreshed['proxies'].removeAt(0);
      expect(
        () => assembleChains(refreshed, [chain()], ChainCatalog(refreshed)),
        throwsFormatException,
      );
      expect(
        () => assembleChains(source(), [
          chain(entries: ['removed']),
        ], ChainCatalog(source())),
        throwsFormatException,
      );
    },
  );

  test('provider references survive reordering and group filters apply', () {
    final config = source();
    config['proxy-groups'].add({
      'name': 'provider',
      'type': 'select',
      'use': ['sub'],
      'filter': '^HK',
      'exclude-filter': 'bad',
    });
    final providers = {
      'sub': [node('HK1'), node('US'), node('HKbad')],
    };
    final catalog = ChainCatalog(config, providers: providers);
    final hop = catalog.groups['provider']!.single;
    final route = chain(hops: [hop]);
    final reordered = ChainCatalog(
      config,
      providers: {
        'sub': [node('US'), node('HK1', server: 'updated.example.com')],
      },
    );
    expect(
      reordered.compile(route, {}).generatedProxies.values.single['server'],
      'updated.example.com',
    );
    expect(
      catalog
          .compile(chain(hops: const [ChainTarget.group('provider')]), {})
          .paths,
      hasLength(1),
    );
    final missing = ChainCatalog(
      config,
    ).compile(chain(hops: const [ChainTarget.group('provider')]), {});
    expect(missing.isValid, isFalse);
    expect(missing.diagnostics.first.message, contains('missing-provider:sub'));
  });

  test('include-all-proxies excludes provider nodes from other groups', () {
    final config = source();
    config['proxy-groups'].insert(0, {
      'name': 'provider',
      'type': 'select',
      'use': ['sub'],
    });
    config['proxy-groups'].add({
      'name': 'all',
      'type': 'select',
      'include-all-proxies': true,
    });
    final catalog = ChainCatalog(
      config,
      providers: {
        'sub': [node('provider-node')],
      },
    );
    expect(catalog.groups['all']!.map((target) => target.id), ['A', 'B']);
  });

  test('validates empty chains, ports and existing dialer replacement', () {
    final catalog = ChainCatalog(source());
    expect(catalog.compile(chain(hops: []), {}).isValid, isFalse);
    expect(
      catalog
          .compile(
            chain(
              hops: const [
                ChainTarget.localEndpoint({
                  'type': 'socks5',
                  'server': '127.0.0.1',
                  'port': 0,
                }),
              ],
            ),
            {},
          )
          .isValid,
      isFalse,
    );
    catalog.nodes['A']!['dialer-proxy'] = 'outside';
    final result = catalog.compile(chain(), {});
    expect(
      result.diagnostics.map((d) => d.code),
      contains('existing-dialer-proxy'),
    );
    expect(result.generatedProxies.values.first['dialer-proxy'], isNull);
    expect(catalog.nodes['A']!['dialer-proxy'], 'outside');
  });

  test(
    'library roundtrip, concurrent updates, merge and override recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bettbox_chain_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = ChainStore(File('${directory.path}/$chainLibraryFileName'));
      expect(await store.load(), isEmpty);
      final endpoint = chain(
        hops: const [
          ChainTarget.localEndpoint({
            'name': 'local',
            'type': 'http',
            'server': 'localhost',
            'port': 8888,
            'password': 'test-only',
          }),
        ],
      );
      await Future.wait([store.put(endpoint), store.put(chain(id: '2'))]);
      expect(await store.load(), hasLength(2));
      final restored = ChainStore.decode(ChainStore.encode(await store.load()));
      expect(restored.first.hops.single.config!['password'], 'test-only');
      await store.restore(ChainStore.encode([chain(id: '3')]), replace: false);
      expect(await store.load(), hasLength(3));
      await store.restore(ChainStore.encode([chain(id: '3')]), replace: true);
      expect((await store.load()).single.id, '3');
      await expectLater(
        store.restore('{"version":2,"chains":[]}', replace: true),
        throwsFormatException,
      );
      expect((await store.load()).single.id, '3');
      await store.delete('3');
      expect(await store.load(), isEmpty);
    },
  );
}
