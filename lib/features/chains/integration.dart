import 'dart:convert';
import 'dart:io';

import 'package:bett_box/common/common.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import 'assembler.dart';
import 'store.dart';

Future<ChainStore>? _store;

Future<ChainStore> getChainStore() => _store ??= _createStore();

Future<ChainStore> _createStore() async =>
    ChainStore(File(join(await appPath.homeDirPath, chainLibraryFileName)));

Future<ChainCatalog> loadChainCatalog(
  String profileId,
  Map<String, dynamic> config,
) async {
  final providers = <String, List<Map<String, dynamic>>>{};
  final home = await appPath.homeDirPath;
  final rawProviders = config['proxy-providers'] as Map? ?? {};
  for (final entry in rawProviders.entries) {
    final provider = entry.value as Map;
    dynamic payload = provider['payload'];
    if (payload == null) {
      String? path = provider['path'] as String?;
      if (provider['type'] == 'http' && provider['url'] is String) {
        path = await appPath.getProvidersFilePath(
          profileId,
          'proxies',
          provider['url'] as String,
        );
      }
      if (path != null) {
        final file = File(isAbsolute(path) ? path : join(home, path));
        if (await file.exists()) {
          final document = jsonDecode(
            jsonEncode(loadYaml(await file.readAsString())),
          );
          if (document is Map) payload = document['proxies'];
        }
      }
    }
    if (payload == null) continue;
    final filter = provider['filter'] is String
        ? RegExp(provider['filter'] as String)
        : null;
    final exclude = provider['exclude-filter'] is String
        ? RegExp(provider['exclude-filter'] as String)
        : null;
    providers[entry.key.toString()] = [
      for (final raw in payload as List? ?? [])
        if ((filter == null || filter.hasMatch(raw['name'].toString())) &&
            (exclude == null || !exclude.hasMatch(raw['name'].toString())))
          Map<String, dynamic>.from(raw as Map),
    ];
  }
  return ChainCatalog(config, providers: providers);
}

Future<Map<String, dynamic>> applyProxyChains(
  String profileId,
  Map<String, dynamic> config,
) async {
  final chains = (await (await getChainStore()).load())
      .where((chain) => chain.enabled && chain.profileId == profileId)
      .toList();
  if (chains.isEmpty) return config;
  return assembleChains(
    config,
    chains,
    await loadChainCatalog(profileId, config),
  );
}
