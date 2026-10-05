import 'dart:convert';

import 'package:bett_box/features/chains/assembler.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/persistence.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const source = '''# profile comment
proxies:
  - {name: entry, type: socks5, server: entry.example, port: 1080}
  - {name: exit, type: socks5, server: exit.example, port: 1080}
proxy-groups:
  - {name: main, type: select, proxies: [entry, exit]}
  - {name: auto, type: select, include-all: true, exclude-filter: original}
# keep routing comment
rules:
  - MATCH,main
proxy-providers: {}
''';

ProxyChain chain(String id, {bool hidden = true, bool enabled = true}) =>
    ProxyChain(
      id: id,
      name: 'route$id',
      profileId: 'p',
      hidden: hidden,
      enabled: enabled,
      hops: const [ChainTarget.node('entry'), ChainTarget.node('exit')],
      entryGroups: const ['main', 'auto'],
    );

String write(String content, List<ProxyChain> chains) => writeChainsToProfile(
  content,
  chains,
  ChainCatalog(chainProfileBase(content)),
);

void main() {
  test(
    'multiple chains persist in one YAML and deleting restores only additions',
    () {
      final first = write(source, [chain('1')]);
      final both = write(first, [chain('1'), chain('2')]);
      final config = loadYaml(both) as Map;
      expect((config['proxy-groups'] as List).map((g) => g['name']), [
        'main',
        'auto',
        'route1',
        'route2',
      ]);
      expect(config['proxy-groups'][0]['proxies'], [
        'entry',
        'exit',
        'route1',
        'route2',
      ]);
      expect(
        both.substring(both.indexOf('# keep routing comment')),
        source.substring(source.indexOf('# keep routing comment')),
      );
      final deleted = write(both, [chain('2')]);
      expect(deleted, isNot(contains('route1')));
      expect(deleted, contains('route2'));
      final restored = write(deleted, []);
      expect(jsonEncode(loadYaml(restored)), jsonEncode(loadYaml(source)));
      expect(
        removePersistedChains(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(config))),
        ),
        chainProfileBase(source),
      );
    },
  );

  test(
    'rebuilding preserves later unrelated edits and hidden/disabled state',
    () {
      final saved = write(source, [chain('1')]);
      var edited = appendNodesToProfile(saved, [
        {
          'name': 'later',
          'type': 'socks5',
          'server': 'later.example',
          'port': 1080,
        },
      ]);
      final config =
          jsonDecode(jsonEncode(loadYaml(edited))) as Map<String, dynamic>;
      config['proxy-groups'][1]['exclude-filter'] =
          'later`${config['proxy-groups'][1]['exclude-filter']}';
      edited = replaceProfileSection(
        edited,
        'proxy-groups',
        config['proxy-groups'],
      );
      final visible =
          loadYaml(write(edited, [chain('1', hidden: false)])) as Map;
      expect(visible['proxy-groups'].last['hidden'], false);
      final disabled =
          loadYaml(write(edited, [chain('1', enabled: false)])) as Map;
      expect((disabled['proxies'] as List).last['name'], 'later');
      expect(disabled['proxy-groups'][1]['exclude-filter'], 'later`original');
      expect(disabled['proxy-groups'].length, 2);
    },
  );

  test(
    'shared imported nodes are removed only after their final chain is deleted',
    () {
      final external = {
        'name': 'imported',
        'type': 'socks5',
        'server': 'external.example',
        'port': 1080,
      };
      ProxyChain externalChain(String id) => ProxyChain(
        id: id,
        name: 'external$id',
        profileId: 'p',
        hops: const [ChainTarget.node('entry'), ChainTarget.node('imported')],
        externalNodes: [external],
      );
      final both = write(source, [externalChain('1'), externalChain('2')]);
      final one = write(both, [externalChain('2')]);
      expect(
        (loadYaml(one)['proxies'] as List)
            .where((n) => n['name'] == 'imported')
            .length,
        1,
      );
      expect(
        jsonEncode(loadYaml(write(one, []))),
        jsonEncode(loadYaml(source)),
      );
    },
  );

  test(
    'hidden defaults survive old libraries and local snapshots have no managed markers',
    () {
      final restored = ProxyChain.fromJson(
        chain('1').toJson()..remove('hidden'),
      );
      expect(restored.hidden, true);
      final snapshot = createChainProfileConfig(
        chainProfileBase(source),
        restored,
        ChainCatalog(chainProfileBase(source)),
      );
      expect(snapshot['proxy-groups'].last['hidden'], true);
      expect(jsonEncode(snapshot), isNot(contains('x-bettbox-chain-id')));
      expect(removePersistedChains(snapshot), snapshot);
    },
  );

  test('section updates support flow YAML, aliases, empty sections and CRLF', () {
    for (final yaml in [
      'proxies:\nproxy-groups: []\nrules: ["MATCH,DIRECT"]\n',
      '{proxies: [], proxy-groups: [], rules: ["MATCH,DIRECT"]}',
      'common: &nodes [{name: original}]\nproxies: *nodes\nrules: ["MATCH,DIRECT"]\n',
      'proxies: &nodes [{name: original}]\nother: *nodes\nrules: ["MATCH,DIRECT"]\n',
      'proxies:\n  - {name: original}\n# rules\nrules: ["MATCH,DIRECT"]\n',
      'rules: ["MATCH,DIRECT"]\n',
    ]) {
      for (final content in [yaml, yaml.replaceAll('\n', '\r\n')]) {
        final updated = replaceProfileSection(content, 'proxies', []);
        expect(loadYaml(updated)['proxies'], isEmpty, reason: updated);
        expect(loadYaml(updated)['rules'], loadYaml(content)['rules']);
        if (content.contains('common:')) {
          expect(loadYaml(updated)['common'], loadYaml(content)['common']);
        }
        if (content.contains('\r\n')) {
          expect(updated.replaceAll('\r\n', ''), isNot(contains('\n')));
        }
      }
    }
  });

  test(
    'node deletion cleans memberships/dialers and retains other sections',
    () {
      final input = source.replaceFirst(
        'port: 1080}',
        'port: 1080, dialer-proxy: exit}',
      );
      final updated = removeNodesFromProfile(input, {'exit'});
      final config = loadYaml(updated) as Map;
      expect(config['proxies'].length, 1);
      expect(config['proxies'][0]['dialer-proxy'], isNull);
      expect(config['proxy-groups'][0]['proxies'], ['entry']);
      expect(
        updated.substring(updated.indexOf('# keep routing comment')),
        input.substring(input.indexOf('# keep routing comment')),
      );
      final empty = loadYaml(removeNodesFromProfile(input, {'entry', 'exit'}));
      expect(empty['proxies'], isEmpty);
      expect(empty['proxy-groups'][0]['proxies'], ['DIRECT']);
    },
  );
}
