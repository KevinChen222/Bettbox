import 'compiler.dart';

class ProxyChain {
  const ProxyChain({
    required this.id,
    required this.name,
    required this.profileId,
    required this.hops,
    this.entryGroups = const [],
    this.enabled = true,
    this.branchLimit = 64,
  });

  final String id;
  final String name;
  final String profileId;
  final List<ChainTarget> hops;
  final List<String> entryGroups;
  final bool enabled;
  final int branchLimit;

  factory ProxyChain.fromJson(Map<String, dynamic> json) => ProxyChain(
    id: json['id'] as String,
    name: json['name'] as String,
    profileId: json['profileId'] as String,
    enabled: json['enabled'] as bool? ?? true,
    branchLimit: json['branchLimit'] as int? ?? 64,
    entryGroups: List<String>.from(json['entryGroups'] as List? ?? []),
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
    'branchLimit': branchLimit,
    'entryGroups': entryGroups,
    'hops': [
      for (final hop in hops)
        {'kind': hop.kind.name, 'id': hop.id, 'config': hop.config},
    ],
  };
}
