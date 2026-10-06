import 'dart:convert';
import 'dart:io';

import 'package:bett_box/common/path.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/integration.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/persistence.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:bett_box/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
// PathProvider's platform interface is used only to replace native I/O in tests.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class TestPaths extends PathProviderPlatform {
  TestPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String> getTemporaryPath() async => root;
  @override
  Future<String> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'bettbox_chain_integration_',
    );
    PathProviderPlatform.instance = TestPaths(directory.path);
    await appPath.dataDir.future;
  });
  tearDownAll(() => directory.delete(recursive: true));

  test(
    'profile refresh retains additions while updating the airport configuration',
    () async {
      final incoming = File('${directory.path}/subscription.yaml');
      await incoming.writeAsString(
        'proxies: [{name: airport, type: socks5, server: old.example, port: 1080}]\nrules: [MATCH,DIRECT]\n',
      );
      final manual = {
        'name': 'manual',
        'type': 'socks5',
        'server': 'manual.example',
        'port': 1080,
      };
      var profile = Profile.normal(url: Uri.file(incoming.path).toString())
          .copyWith(
            addedNodes: [manual],
            addedProviders: {
              'extra': subscriptionProvider(
                'extra',
                'https://example.com/sub',
                {},
              ),
            },
          );
      profile = await profile.update(validate: false);
      expect(profile.autoUpdate, true);
      final saved =
          loadYaml(await (await profile.getFile()).readAsString()) as Map;
      expect(saved['proxies'].map((node) => node['name']), [
        'manual',
        'airport',
      ]);
      await incoming.writeAsString(
        'proxies: [{name: airport-new, type: socks5, server: new.example, port: 1080}]\nrules: [MATCH,REJECT]\ndns: {enable: true}\n',
      );
      profile = await profile.update(validate: false);
      final updated =
          loadYaml(await (await profile.getFile()).readAsString()) as Map;
      expect(updated['proxies'].map((node) => node['name']), [
        'manual',
        'airport-new',
      ]);
      expect(updated['proxy-providers']['extra']['interval'], 86400);
      expect(updated['rules'], ['MATCH', 'REJECT']);
      expect(updated['dns']['enable'], true);
      profile = await profile
          .copyWith(addedNodes: [], addedProviders: {})
          .update(validate: false);
      final deleted =
          loadYaml(await (await profile.getFile()).readAsString()) as Map;
      expect(deleted['proxies'].map((node) => node['name']), ['airport-new']);
      expect(deleted['proxy-providers'], isNull);
    },
  );

  test(
    'local snapshots seed both HTTP caches before profile path rewriting',
    () async {
      final config = <String, dynamic>{};
      for (final type in {
        'proxy-providers': 'proxies',
        'rule-providers': 'rules',
      }.entries) {
        final url = 'https://example.com/${type.value}';
        final original = File(
          await appPath.getProvidersFilePath('source', type.value, url),
        );
        await original.parent.create(recursive: true);
        await original.writeAsBytes([0, 1, 2, 255]);
        config[type.key] = {
          'cached': {'type': 'http', 'url': url, 'path': original.path},
        };
      }
      await seedLocalProfileProviderCaches('snapshot', config);
      for (final type in ['proxies', 'rules']) {
        final cache = File(
          await appPath.getProvidersFilePath(
            'snapshot',
            type,
            'https://example.com/$type',
          ),
        );
        expect(await cache.readAsBytes(), [0, 1, 2, 255]);
        await cache.writeAsBytes([3, 4]);
      }
      await seedLocalProfileProviderCaches('snapshot', config);
      for (final type in ['proxies', 'rules']) {
        final cache = File(
          await appPath.getProvidersFilePath(
            'snapshot',
            type,
            'https://example.com/$type',
          ),
        );
        expect(await cache.readAsBytes(), [3, 4]);
      }
    },
  );

  test('runtime applies only enabled chains for the target profile', () async {
    final store = await getChainStore();
    final config = <String, dynamic>{
      'proxies': [
        {'name': 'A', 'type': 'socks5', 'server': 'example.com', 'port': 1080},
      ],
      'proxy-groups': <dynamic>[],
    };
    for (final id in ['one', 'two']) {
      await store.put(
        ProxyChain(
          id: id,
          name: id,
          profileId: id,
          hops: const [ChainTarget.node('A')],
        ),
      );
    }
    await store.put(
      const ProxyChain(
        id: 'disabled',
        name: 'disabled',
        profileId: 'one',
        enabled: false,
        hops: [ChainTarget.node('missing')],
      ),
    );
    final result = await applyProxyChains('one', config);
    expect((result['proxy-groups'] as List).single['name'], 'one');
    expect(await applyProxyChains('unbound', config), same(config));
    expect(config['proxy-groups'], isEmpty);
    final persisted = assembleChains(
      config,
      (await store.load()).where((chain) => chain.id == 'one').toList(),
      await loadChainCatalog('one', config),
      persist: true,
    );
    expect(await applyProxyChains('one', persisted), same(persisted));
    expect((persisted['proxy-groups'] as List).single['hidden'], true);
  });

  test(
    'saves and copies two-hop chains using anchored HTTP provider caches',
    () async {
      final cache = File(
        await appPath.getProvidersFilePath(
          'profile',
          'proxies',
          'https://example.com/sub',
        ),
      );
      await cache.parent.create(recursive: true);
      await cache.writeAsString(
        'proxies:\n  - name: HK\n    type: socks5\n    server: updated.example.com\n    port: 1080\n',
      );
      const source = '''p: &p {type: http, interval: 86400}
proxy-providers:
  sub:
    <<: *p
    url: https://example.com/sub
    path: unused.yaml
proxy-groups:
  - {name: provider, type: select, use: [sub]}
rules: [MATCH,provider]
''';
      final config = chainProfileBase(source);
      Future<List<Map<String, dynamic>>> parse(
        List<int> content,
        Map<String, dynamic> provider,
      ) async {
        expect(provider['type'], 'http');
        return [
          for (final node in loadYaml(utf8.decode(content))['proxies'])
            Map<String, dynamic>.from(node as Map),
        ];
      }

      final catalog = await loadChainCatalog(
        'profile',
        config,
        parseProviderNodes: parse,
      );
      final result = catalog.compile(
        const ProxyChain(
          id: '1',
          name: 'provider route',
          profileId: 'profile',
          hops: [ChainTarget.group('provider')],
        ),
        {},
      );
      expect(
        result.generatedProxies.values.single['server'],
        'updated.example.com',
      );
      const chain = ProxyChain(
        id: 'original',
        name: 'route',
        profileId: 'profile',
        hops: [
          ChainTarget.group('provider'),
          ChainTarget.node('provider:["sub","HK"]'),
        ],
      );
      final saved = writeChainsToProfile(source, [chain], catalog);
      final copied = writeChainsToProfile(
        saved,
        [
          chain,
          const ProxyChain(
            id: 'copy',
            name: 'route (copy)',
            profileId: 'profile',
            hops: [
              ChainTarget.group('provider'),
              ChainTarget.node('provider:["sub","HK"]'),
            ],
          ),
        ],
        await loadChainCatalog(
          'profile',
          chainProfileBase(saved),
          parseProviderNodes: parse,
        ),
      );
      expect(
        (loadYaml(copied)['proxy-groups'] as List)
            .where((group) => group['x-bettbox-chain-id'] != null)
            .length,
        2,
      );
      expect(copied, contains('<<: *p'));
      await cache.delete();
      final missing = await loadChainCatalog(
        'profile',
        config,
        parseProviderNodes: parse,
      );
      expect(
        missing
            .compile(
              const ProxyChain(
                id: '1',
                name: 'route',
                profileId: 'profile',
                hops: [ChainTarget.group('provider')],
              ),
              {},
            )
            .isValid,
        isFalse,
      );
    },
  );

  test(
    'passes local and inline contents and provider options to the core parser',
    () async {
      final file = File('${await appPath.homeDirPath}/local.yaml');
      await file.writeAsString(
        jsonEncode({
          'proxies': [
            {
              'name': 'HK',
              'type': 'socks5',
              'server': 'hk.example.com',
              'port': 1080,
            },
            {
              'name': 'US',
              'type': 'socks5',
              'server': 'us.example.com',
              'port': 1080,
            },
          ],
        }),
      );
      final calls = <Map<String, dynamic>>[];
      final catalog = await loadChainCatalog(
        'profile',
        {
          'proxy-providers': {
            'file': {'type': 'file', 'path': 'local.yaml', 'filter': '(?i)^hk'},
            'inline': {
              'type': 'inline',
              'exclude-filter': '(?i)BLOCKED',
              'payload': [
                {
                  'name': 'blocked',
                  'type': 'http',
                  'server': 'localhost',
                  'port': 8080,
                },
                {
                  'name': 'local',
                  'type': 'http',
                  'server': 'localhost',
                  'port': 8080,
                },
              ],
            },
          },
          'proxy-groups': [
            {'name': 'all', 'type': 'select', 'include-all-providers': true},
          ],
        },
        parseProviderNodes: (content, provider) async {
          calls.add(provider);
          final nodes = loadYaml(utf8.decode(content))['proxies'] as List;
          // The native parser's filters are covered by Go regression tests.
          return [
            Map<String, dynamic>.from(
              nodes.firstWhere(
                    (node) =>
                        node['name'] ==
                        (provider['type'] == 'file' ? 'HK' : 'local'),
                  )
                  as Map,
            ),
          ];
        },
      );
      expect(catalog.nodes.values.map((node) => node['name']), ['HK', 'local']);
      expect(calls[0]['filter'], '(?i)^hk');
      expect(calls[1]['exclude-filter'], '(?i)BLOCKED');
    },
  );
}
