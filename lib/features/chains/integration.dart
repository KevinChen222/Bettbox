import 'dart:convert';
import 'dart:io';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/common.dart';
import 'package:path/path.dart';

import 'assembler.dart';
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
  Map<String, dynamic> config, {
  Future<List<Map<String, dynamic>>> Function(
    List<int> content,
    Map<String, dynamic> provider,
  )?
  parseProviderNodes,
}) async {
  final providers = <String, List<Map<String, dynamic>>>{};
  final home = await appPath.homeDirPath;
  final rawProviders = config['proxy-providers'] as Map? ?? {};
  for (final entry in rawProviders.entries) {
    final provider = entry.value as Map;
    List<int>? content;
    if (provider['type'] != 'inline') {
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
          content = await file.readAsBytes();
        }
      }
    }
    if (content == null && provider['payload'] != null) {
      content = utf8.encode(jsonEncode({'proxies': provider['payload']}));
    }
    if (content == null) continue;
    providers[entry.key.toString()] =
        await (parseProviderNodes ?? clashCore.parseProviderNodes)(
          content,
          Map<String, dynamic>.from(provider),
        );
  }
  return ChainCatalog(config, providers: providers);
}

Future<Map<String, dynamic>> applyProxyChains(
  String profileId,
  Map<String, dynamic> config, {
  void Function(String)? onInvalidChain,
}) async {
  config = isolateBrokenPersistedChains(config);
  final persistedIds = {
    for (final group in config['proxy-groups'] as List? ?? [])
      if (group['x-bettbox-chain-id'] != null) group['x-bettbox-chain-id'],
  };
  final chains = (await (await getChainStore()).load())
      .where(
        (chain) =>
            chain.enabled &&
            chain.profileId == profileId &&
            !persistedIds.contains(chain.id),
      )
      .toList();
  final result = chains.isEmpty
      ? config
      : assembleChains(
          config,
          chains,
          await loadChainCatalog(profileId, config),
          allowInvalidChains: true,
        );
  for (final group in result['proxy-groups'] as List? ?? []) {
    final error = group['x-bettbox-chain-error'];
    if (error is String) onInvalidChain?.call(error);
  }
  return result;
}
