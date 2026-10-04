import 'dart:convert';
import 'dart:io';

import 'package:synchronized/synchronized.dart';

import 'model.dart';

const chainLibraryFileName = 'proxy-chains.json';

class ChainStore {
  ChainStore(this.file);

  final File file;
  final Lock _lock = Lock();

  static List<ProxyChain> decode(String content) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported chain library version');
    }
    final chains = [
      for (final item in json['chains'] as List)
        ProxyChain.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    final ids = <String>{};
    for (final chain in chains) {
      if (chain.id.isEmpty ||
          !ids.add(chain.id) ||
          chain.name.trim().isEmpty ||
          chain.profileId.isEmpty ||
          chain.hops.isEmpty ||
          chain.hops.length > 16 ||
          chain.branchLimit < 1 ||
          chain.branchLimit > 1024) {
        throw const FormatException('Invalid chain library');
      }
    }
    return chains;
  }

  static String encode(List<ProxyChain> chains) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'chains': chains.map((chain) => chain.toJson()).toList(),
      });

  Future<List<ProxyChain>> load() => _lock.synchronized(_read);

  Future<List<ProxyChain>> _read() async =>
      await file.exists() ? decode(await file.readAsString()) : [];

  Future<void> _write(List<ProxyChain> chains) async {
    final content = encode(chains);
    decode(content);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> put(ProxyChain chain) => _lock.synchronized(() async {
    final chains = await _read();
    final index = chains.indexWhere((item) => item.id == chain.id);
    if (index < 0) {
      chains.add(chain);
    } else {
      chains[index] = chain;
    }
    await _write(chains);
  });

  Future<void> delete(String id) => _lock.synchronized(() async {
    final chains = await _read()
      ..removeWhere((chain) => chain.id == id);
    await _write(chains);
  });

  Future<void> restore(String content, {required bool replace}) =>
      _lock.synchronized(() async {
        final incoming = decode(content);
        final existing = replace ? <ProxyChain>[] : await _read();
        final merged = {for (final chain in existing) chain.id: chain};
        for (final chain in incoming) {
          merged[chain.id] = chain;
        }
        await _write(merged.values.toList());
      });
}
