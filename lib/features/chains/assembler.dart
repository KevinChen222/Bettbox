import 'dart:convert';

import 'compiler.dart';
import 'filter.dart';
import 'model.dart';

/// Source nodes and group members. An entry group remains a live reference;
/// downstream group hops resolve to node copies.
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

  ChainCompileResult compile(
    ProxyChain chain,
    Set<String> reserved, [
    Map<String, Map<String, dynamic>> existingNodes = const {},
  ]) => DialerChainCompiler().compile(
    ChainCompileRequest(
      name: chain.name,
      hops: chain.hops.map((hop) => ChainHop(target: hop)).toList(),
      nodes: {
        ...nodes,
        ...existingNodes,
        for (final node in chain.externalNodes) node['name'] as String: node,
      },
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
  ChainCatalog catalog, {
  bool persist = false,
}) {
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
    for (final node in chain.externalNodes) {
      final name = node['name'];
      if (name is! String || name.isEmpty || node['type'] is! String) {
        throw FormatException('${chain.name}: Invalid external node');
      }
      if (reserved.contains(name)) {
        final existing = proxies
            .where((raw) => raw['name'] == name)
            .firstOrNull;
        final original = existing == null
            ? null
            : (Map<String, dynamic>.from(existing as Map)
                ..remove('x-bettbox-chain-id'));
        if (original == null || jsonEncode(original) != jsonEncode(node)) {
          throw FormatException(
            '${chain.name}: External node name conflict: $name',
          );
        }
      } else {
        proxies.add({
          ...jsonDecode(jsonEncode(node)) as Map<String, dynamic>,
          if (persist) 'x-bettbox-chain-id': chain.id,
        });
        reserved.add(name);
      }
    }
    final existingNodes = {
      for (final raw in proxies)
        raw['name'] as String: Map<String, dynamic>.from(raw as Map),
    };
    final result = catalog.compile(chain, reserved, existingNodes);
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
      if (chain.hops.length > 1 &&
          _usesGroup(chain.hops.first, entry, catalog, existingNodes, {})) {
        throw FormatException('${chain.name}: 前置依赖策略组 "$entry"，不能将链路加入该组以免循环');
      }
      if (persist) {
        group.putIfAbsent(
          'x-bettbox-chain-had-proxies',
          () => group.containsKey('proxies'),
        );
      }
      group['proxies'] = [...group['proxies'] as List? ?? [], selector.name];
    }
    proxies.addAll(
      result.generatedProxies.values.map(
        (node) => {...node, if (persist) 'x-bettbox-chain-id': chain.id},
      ),
    );
    groups.add({
      ...selector.toConfig(),
      'hidden': chain.hidden,
      if (persist) 'x-bettbox-chain-id': chain.id,
    });
    reserved.addAll(result.generatedProxies.keys);
    reserved.add(selector.name);
  }
  final generatedNames = proxies
      .skip((source['proxies'] as List? ?? []).length)
      .map(
        (raw) => RegExp.escape(raw['name'] as String).replaceAll('`', r'\x60'),
      )
      .join('|');
  if (generatedNames.isNotEmpty) {
    // include-all groups must not discover their own downstream copies.
    for (final group in groups.take(
      (source['proxy-groups'] as List? ?? []).length,
    )) {
      if (group['include-all'] != true &&
          group['include-all-proxies'] != true) {
        continue;
      }
      final exclude = group['exclude-filter'] as String? ?? '';
      if (persist) {
        group['x-bettbox-chain-exclude-filter'] = {
          'added': '^($generatedNames)\$',
          'hadKey': group.containsKey('exclude-filter'),
        };
      }
      group['exclude-filter'] =
          '${exclude.isEmpty ? '' : '$exclude`'}^($generatedNames)\$';
    }
  }
  config['proxies'] = proxies;
  config['proxy-groups'] = groups;
  return config;
}

/// Remove only additions marked by this client, retaining unrelated YAML edits.
Map<String, dynamic> removePersistedChains(Map<String, dynamic> source) {
  final config = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final groups = config['proxy-groups'] as List? ?? [];
  final names = {
    for (final group in groups)
      if (group['x-bettbox-chain-id'] != null) group['name'],
  };
  (config['proxies'] as List?)?.removeWhere(
    (node) => node['x-bettbox-chain-id'] != null,
  );
  groups.removeWhere((group) => group['x-bettbox-chain-id'] != null);
  for (final group in groups) {
    final hadProxies = group.remove('x-bettbox-chain-had-proxies');
    (group['proxies'] as List?)?.removeWhere(names.contains);
    if (hadProxies == false && (group['proxies'] as List).isEmpty) {
      group.remove('proxies');
    }
    final filter = group.remove('x-bettbox-chain-exclude-filter') as Map?;
    if (filter != null) {
      final parts = (group['exclude-filter'] as String? ?? '').split('`')
        ..remove(filter['added']);
      final remaining = parts.join('`');
      if (remaining.isEmpty && filter['hadKey'] == false) {
        group.remove('exclude-filter');
      } else {
        group['exclude-filter'] = remaining;
      }
    }
  }
  return config;
}

bool _usesGroup(
  ChainTarget target,
  String group,
  ChainCatalog catalog,
  Map<String, Map<String, dynamic>> existingNodes,
  Set<String> visited,
) {
  if (!visited.add('${target.kind}:${target.id}')) return false;
  if (target.kind == ChainTargetKind.group) {
    return target.id == group ||
        (catalog.groups[target.id] ?? []).any(
          (member) =>
              _usesGroup(member, group, catalog, existingNodes, visited),
        );
  }
  final dialer =
      (target.config ??
      existingNodes[target.id] ??
      catalog.nodes[target.id])?['dialer-proxy'];
  if (dialer is! String) return false;
  return _usesGroup(
    catalog.groups.containsKey(dialer)
        ? ChainTarget.group(dialer)
        : ChainTarget.node(dialer),
    group,
    catalog,
    existingNodes,
    visited,
  );
}

/// Keep the source routing rules when creating a local snapshot or YAML export.
Map<String, dynamic> createChainProfileConfig(
  Map<String, dynamic> source,
  ProxyChain chain,
  ChainCatalog catalog,
) => assembleChains(source, [chain], catalog);
