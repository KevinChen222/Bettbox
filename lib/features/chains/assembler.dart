import 'dart:convert';

import 'compiler.dart';
import 'filter.dart';
import 'model.dart';

/// A snapshot of source nodes and group members. Group hops expand to paths;
/// they do not change or follow the source group's live selection.
class ChainCatalog {
  ChainCatalog(Map<String, dynamic> config, {this.providers = const {}}) {
    for (final raw in config['proxies'] as List? ?? []) {
      final node = Map<String, dynamic>.from(raw as Map);
      nodes[node['name'] as String] = node;
    }
    final rawGroups = config['proxy-groups'] as List? ?? [];
    final sourceNodes = nodes.keys.toList();
    final providerTargets = <String, List<ChainTarget>>{};
    for (final entry in providers.entries) {
      final targets = <ChainTarget>[];
      for (final node in entry.value) {
        final id = 'provider:${jsonEncode([entry.key, node['name']])}';
        if (nodes.containsKey(id)) {
          throw FormatException(
            'Duplicate provider node: ${entry.key} / ${node['name']}',
          );
        }
        nodes[id] = node;
        targets.add(ChainTarget.node(id));
      }
      providerTargets[entry.key] = targets;
    }
    final groupNames = {
      for (final raw in rawGroups) (raw as Map)['name'] as String,
    };
    final groupTypes = {
      for (final raw in rawGroups)
        (raw as Map)['name']: raw['type'].toString().toLowerCase(),
    };
    for (final raw in rawGroups) {
      final group = raw as Map;
      final filter = _patterns(group['filter']);
      final exclude = _patterns(group['exclude-filter']);
      final members = <ChainTarget>[];
      for (final name in group['proxies'] as List? ?? []) {
        if (nodes.containsKey(name)) {
          members.add(ChainTarget.node(name as String));
        } else if (groupNames.contains(name)) {
          members.add(ChainTarget.group(name as String));
        }
      }
      if (group['include-all'] == true ||
          group['include-all-proxies'] == true) {
        members.addAll(
          sourceNodes
              .where(
                (id) =>
                    filter.isEmpty ||
                    filter.any(
                      (regex) => regex.hasMatch(nodes[id]!['name'].toString()),
                    ),
              )
              .map(ChainTarget.node),
        );
      }
      final providerNames =
          group['include-all'] == true || group['include-all-providers'] == true
          ? providers.keys
          : (group['use'] as List? ?? []).cast<String>();
      for (final provider in providerNames) {
        if (!providers.containsKey(provider)) {
          members.add(ChainTarget.node('missing-provider:$provider'));
        }
        members.addAll(
          (providerTargets[provider] ?? const <ChainTarget>[]).where(
            (target) =>
                filter.isEmpty ||
                filter.any(
                  (regex) =>
                      regex.hasMatch(nodes[target.id]!['name'].toString()),
                ),
          ),
        );
      }
      final excludedTypes =
          (group['exclude-type']?.toString().toLowerCase() ?? '').split('|');
      final seen = <String>{};
      groups[group['name'] as String] = members.where((member) {
        if (!seen.add('${member.kind.name}:${member.id}')) return false;
        final node = nodes[member.id];
        if (node == null && member.kind != ChainTargetKind.group) return true;
        final name = node?['name'].toString() ?? member.id!;
        final type =
            node?['type'].toString().toLowerCase() ?? groupTypes[member.id];
        return !exclude.any((regex) => regex.hasMatch(name)) &&
            !excludedTypes.contains(type);
      }).toList();
    }
  }

  final Map<String, List<Map<String, dynamic>>> providers;
  final nodes = <String, Map<String, dynamic>>{};
  final groups = <String, List<ChainTarget>>{};

  static List<RegExp> _patterns(dynamic value) =>
      value is String && value.isNotEmpty
      ? value.split('`').map(chainFilter).toList()
      : [];

  ChainCompileResult compile(ProxyChain chain, Set<String> reserved) =>
      DialerChainCompiler().compile(
        ChainCompileRequest(
          name: chain.name,
          hops: chain.hops.map((hop) => ChainHop(target: hop)).toList(),
          nodes: nodes,
          groups: groups,
          branchLimit: chain.branchLimit,
          generatedPrefix: '__bettbox_chain_${chain.id}',
          reservedNames: reserved,
        ),
      );
}

Map<String, dynamic> assembleChains(
  Map<String, dynamic> source,
  List<ProxyChain> chains,
  ChainCatalog catalog,
) {
  if (chains.isEmpty) return source;
  final config = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final proxies = List<dynamic>.from(config['proxies'] as List? ?? []);
  final groups = List<dynamic>.from(config['proxy-groups'] as List? ?? []);
  final reserved = <String>{
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
    'GLOBAL',
    for (final raw in [...proxies, ...groups]) (raw as Map)['name'] as String,
  };
  for (final chain in chains) {
    final result = catalog.compile(chain, reserved);
    if (!result.isValid) {
      throw FormatException(
        '${chain.name}: ${result.diagnostics.where((d) => d.isError).map((d) => d.message).join('\n')}',
      );
    }
    final selector = result.generatedGroups.single;
    for (final entry in chain.entryGroups) {
      final group = groups.where((raw) => raw['name'] == entry).firstOrNull;
      if (group == null || !catalog.groups.containsKey(entry)) {
        throw FormatException('${chain.name}: 策略组 "$entry" 已不存在，请重新编辑链路绑定');
      }
      if (group['type'] == 'relay') {
        throw FormatException('${chain.name}: 不支持将链路加入 relay 策略组');
      }
      group['proxies'] = [...group['proxies'] as List? ?? [], selector.name];
    }
    proxies.addAll(result.generatedProxies.values);
    groups.add(selector.toConfig());
    reserved.addAll(result.generatedProxies.keys);
    reserved.add(selector.name);
  }
  config['proxies'] = proxies;
  config['proxy-groups'] = groups;
  return config;
}

/// A new local profile or exported config should actually route through its
/// chain, regardless of the source subscription's rule targets.
Map<String, dynamic> createChainProfileConfig(
  Map<String, dynamic> source,
  ProxyChain chain,
  ChainCatalog catalog,
) {
  final config = assembleChains(source, [chain], catalog);
  final selectorName = (config['proxy-groups'] as List).last['name'];
  config['mode'] = 'rule';
  config['rules'] = ['MATCH,$selectorName'];
  return config;
}
