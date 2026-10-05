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
  final base = chainProfileBase(content);
  final generated = assembleChains(
    base,
    chains.where((chain) => chain.enabled).toList(),
    catalog,
    persist: true,
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
