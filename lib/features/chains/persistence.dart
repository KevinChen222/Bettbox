import 'package:bett_box/features/node_import/nodes.dart';
import 'package:yaml/yaml.dart';

import 'assembler.dart';
import 'model.dart';

Map<String, dynamic> chainProfileBase(String content) => removePersistedChains(
  _resolveYamlMerges(loadYaml(content)) as Map<String, dynamic>,
);

// package:yaml preserves << entries; Mihomo expands them before loading.
dynamic _resolveYamlMerges(dynamic value) {
  if (value is List) return value.map(_resolveYamlMerges).toList();
  if (value is! Map) return value;
  final result = <String, dynamic>{};
  final merge = value['<<'];
  for (final inherited in merge is List ? merge : [?merge]) {
    final resolved = _resolveYamlMerges(inherited) as Map<String, dynamic>;
    for (final entry in resolved.entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
  }
  for (final entry in value.entries) {
    if (entry.key != '<<') {
      result[entry.key.toString()] = _resolveYamlMerges(entry.value);
    }
  }
  return result;
}

String writeChainsToProfile(
  String content,
  List<ProxyChain> chains,
  ChainCatalog catalog, {
  bool allowInvalidChains = false,
}) {
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
    allowInvalidChains: allowInvalidChains,
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
