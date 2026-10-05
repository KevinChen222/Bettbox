import 'dart:convert';
import 'dart:io';

import 'package:bett_box/common/path.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/integration.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'loads HTTP provider cache using Bettbox path and current contents',
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
      final config = <String, dynamic>{
        'proxy-providers': {
          'sub': {
            'type': 'http',
            'url': 'https://example.com/sub',
            'path': 'unused.yaml',
          },
        },
        'proxy-groups': [
          {
            'name': 'provider',
            'type': 'select',
            'use': ['sub'],
          },
        ],
      };
      final catalog = await loadChainCatalog('profile', config);
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
      await cache.delete();
      final missing = await loadChainCatalog('profile', config);
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
    'reads local and inline providers and honours provider filters',
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
      final catalog = await loadChainCatalog('profile', {
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
      });
      expect(catalog.nodes.values.map((node) => node['name']), ['HK', 'local']);
    },
  );
}
