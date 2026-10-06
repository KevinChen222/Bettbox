import 'compiler.dart';

class ProxyChain {
  const ProxyChain({
    required this.id,
    required this.name,
    required this.profileId,
    required this.hops,
    this.entryGroups = const [],
    this.externalNodes = const [],
    this.externalSubscriptions = const {},
    this.enabled = true,
    this.hidden = true,
    this.originalAutoUpdate,
    this.branchLimit = 64,
  });

  final String id;
  final String name;
  final String profileId;
  final List<ChainTarget> hops;
  final List<String> entryGroups;
  final List<Map<String, dynamic>> externalNodes;
  final Map<String, List<String>> externalSubscriptions;
  final bool enabled;
  final bool hidden;
  final bool? originalAutoUpdate;
  final int branchLimit;

  factory ProxyChain.fromJson(Map<String, dynamic> json) => ProxyChain(
    id: json['id'] as String,
    name: json['name'] as String,
    profileId: json['profileId'] as String,
    enabled: json['enabled'] as bool? ?? true,
    hidden: json['hidden'] as bool? ?? true,
    originalAutoUpdate: json['originalAutoUpdate'] as bool?,
    branchLimit: json['branchLimit'] as int? ?? 64,
    entryGroups: List<String>.from(json['entryGroups'] as List? ?? []),
    externalNodes: [
      for (final raw in json['externalNodes'] as List? ?? [])
        Map<String, dynamic>.from(raw as Map),
    ],
    externalSubscriptions: {
      for (final entry in (json['externalSubscriptions'] as Map? ?? {}).entries)
        entry.key as String: List<String>.from(entry.value as List),
    },
    hops: [
      for (final raw in json['hops'] as List)
        switch (raw['kind']) {
          'node' => ChainTarget.node(raw['id'] as String),
          'group' => ChainTarget.group(raw['id'] as String),
          'localEndpoint' => ChainTarget.localEndpoint(
            Map<String, dynamic>.from(raw['config'] as Map),
          ),
          _ => throw const FormatException('Unknown chain hop type'),
        },
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'profileId': profileId,
    'enabled': enabled,
    'hidden': hidden,
    if (originalAutoUpdate != null) 'originalAutoUpdate': originalAutoUpdate,
    'branchLimit': branchLimit,
    'entryGroups': entryGroups,
    'externalNodes': externalNodes,
    'externalSubscriptions': externalSubscriptions,
    'hops': [
      for (final hop in hops)
        {'kind': hop.kind.name, 'id': hop.id, 'config': hop.config},
    ],
  };
}
