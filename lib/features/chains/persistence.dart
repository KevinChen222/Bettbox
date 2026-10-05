import 'dart:convert';

import 'package:bett_box/features/node_import/nodes.dart';
import 'package:yaml/yaml.dart';

import 'assembler.dart';
import 'model.dart';

Map<String, dynamic> chainProfileBase(String content) => removePersistedChains(
  jsonDecode(jsonEncode(loadYaml(content))) as Map<String, dynamic>,
);

String writeChainsToProfile(
  String content,
  List<ProxyChain> chains,
  ChainCatalog catalog,
) {
  final previous = loadYaml(content) as Map;
  final preferredNames = <String, Map<String, String>>{};
  for (final chain in chains) {
    final names = <String, String>{};
    for (final group in previous['proxy-groups'] as List? ?? []) {
      if (group['x-bettbox-chain-id'] == chain.id &&
          group['x-bettbox-chain-name'] == chain.name) {
        names['group'] = group['name'] as String;
      }
    }
    for (final node in previous['proxies'] as List? ?? []) {
      if (node['x-bettbox-chain-id'] == chain.id &&
          node['x-bettbox-chain-key'] is String) {
        names[node['x-bettbox-chain-key'] as String] = node['name'] as String;
      }
    }
    if (chain.enabled) preferredNames[chain.id] = names;
  }
  final base = chainProfileBase(content);
  final generated = assembleChains(
    base,
    chains.where((chain) => chain.enabled).toList(),
    catalog,
    persist: true,
    preferredNames: preferredNames,
  );
  var updated = replaceProfileSection(
    content,
    'proxies',
    generated['proxies'] ?? [],
  );
  updated = replaceProfileSection(
    updated,
    'proxy-groups',
    generated['proxy-groups'] ?? [],
  );
  return updated;
}
