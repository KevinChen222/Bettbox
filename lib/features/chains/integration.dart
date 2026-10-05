import 'dart:convert';
import 'dart:io';

import 'package:bett_box/common/common.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import 'assembler.dart';
import 'filter.dart';
import 'store.dart';

Future<ChainStore>? _store;

Future<ChainStore> getChainStore() => _store ??= _createStore();

Future<ChainStore> _createStore() async =>
    ChainStore(File(join(await appPath.homeDirPath, chainLibraryFileName)));

/// A local YAML snapshot still points to its source profile's managed caches.
/// Seed the new profile's paths before the normal path rewrite and core load.
Future<void> seedLocalProfileProviderCaches(
  String profileId,
  Map<String, dynamic> config,
) async {
  final cacheRoot = join(await appPath.profilesPath, 'providers');
  for (final type in {
    'proxy-providers': 'proxies',
    'rule-providers': 'rules',
  }.entries) {
    for (final raw in (config[type.key] as Map? ?? {}).values) {
      final provider = raw as Map;
      final path = provider['path'];
      final url = provider['url'];
      if (provider['type'] != 'http' ||
          path is! String ||
          url is! String ||
          !isAbsolute(path) ||
          !isWithin(cacheRoot, normalize(path))) {
        continue;
      }
      final destination = File(
        await appPath.getProvidersFilePath(profileId, type.value, url),
      );
      final source = File(path);
      if (await destination.exists() || !await source.exists()) continue;
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      await destination.setLastModified(await source.lastModified());
    }
  }
}

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
        ? chainFilter(provider['filter'] as String)
        : null;
    final exclude = provider['exclude-filter'] is String
        ? chainFilter(provider['exclude-filter'] as String)
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
