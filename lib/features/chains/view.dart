import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/features/node_import/menu.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:bett_box/features/node_import/view.dart';
import 'package:bett_box/features/node_import/delete.dart';
import 'package:bett_box/models/models.dart' show Profile, ProfileExtension;
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';

import 'assembler.dart';
import 'compiler.dart';
import 'integration.dart';
import 'model.dart';
import 'persistence.dart';
import 'store.dart';

String _text(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'zh' ? chinese : english;

String proxyChainsTitle(BuildContext context) =>
    _text(context, '代理链路', 'Proxy chains');
String proxyChainsDescription(BuildContext context) => _text(
  context,
  '创建多跳代理，绑定配置与策略组',
  'Create multi-hop routes and bind them to profiles',
);

class ProxyChainsItem extends StatelessWidget {
  const ProxyChainsItem({super.key});

  @override
  Widget build(BuildContext context) => ListItem.next(
    leading: const Icon(Icons.route_outlined),
    title: Text(proxyChainsTitle(context)),
    subtitle: Text(proxyChainsDescription(context)),
    delegate: NextDelegate(
      title: proxyChainsTitle(context),
      builder: (_) => const ProxyChainsView(),
    ),
  );
}

class ProxyChainsView extends StatefulWidget {
  const ProxyChainsView({super.key});

  @override
  State<ProxyChainsView> createState() => _ProxyChainsViewState();
}

class _ProxyChainsViewState extends State<ProxyChainsView> {
  late Future<List<ProxyChain>> _chains = _load();
  bool _busy = false;

  Future<List<ProxyChain>> _load() async => (await getChainStore()).load();

  Future<void> _perform(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) context.showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _chains = _load();
          _busy = false;
        });
      }
    }
  }

  Future<void> _apply() async {
    await globalState.appController.savePreferences();
    if (globalState.isInit) {
      await globalState.appController.applyProfile();
    }
  }

  Future<void> _writeChain(ProxyChain chain, {bool delete = false}) async {
    final store = await getChainStore();
    final previous = await store.load();
    final next = List<ProxyChain>.from(previous);
    final index = next.indexWhere((item) => item.id == chain.id);
    if (delete) {
      next.removeWhere((item) => item.id == chain.id);
    } else if (index < 0) {
      next.add(chain);
    } else {
      next[index] = chain;
    }
    final profile = globalState.config.profiles
        .where((p) => p.id == chain.profileId)
        .firstOrNull;
    if (profile == null) {
      if (!delete) {
        throw const FormatException('Bound profile no longer exists');
      }
      await store.delete(chain.id);
      return;
    }
    final originalAutoUpdate =
        previous
            .where(
              (item) =>
                  item.profileId == profile.id &&
                  item.originalAutoUpdate != null,
            )
            .firstOrNull
            ?.originalAutoUpdate ??
        profile.autoUpdate;
    for (var i = 0; i < next.length; i++) {
      if (next[i].profileId == profile.id) {
        next[i] = ProxyChain.fromJson({
          ...next[i].toJson(),
          'originalAutoUpdate': originalAutoUpdate,
        });
      }
    }
    final profileChains = next
        .where((item) => item.profileId == profile.id)
        .toList();
    final file = File(await appPath.getProfilePath(profile.id));
    final original = await file.readAsString();
    var content = original;
    if (profile.ageSecretKey?.isNotEmpty == true) {
      final decrypted = await clashCore.decryptAgeConfig(
        content,
        profile.ageSecretKey!,
      );
      if (decrypted.isNotEmpty) content = decrypted;
    }
    final base = chainProfileBase(content);
    final updated = writeChainsToProfile(
      content,
      profileChains,
      await loadChainCatalog(profile.id, base),
    );
    final saved = await profile
        .copyWith(
          autoUpdate: profileChains.isEmpty ? originalAutoUpdate : false,
        )
        .saveFileWithString(updated);
    try {
      await store.restore(ChainStore.encode(next), replace: true);
    } catch (_) {
      await file.writeAsString(original, flush: true);
      rethrow;
    }
    globalState.appController.ref
        .read(profilesProvider.notifier)
        .setProfile(saved);
    await _apply();
  }

  Future<void> _edit([ProxyChain? chain]) async {
    final profiles = globalState.config.profiles;
    Profile? profile;
    if (chain != null) {
      profile = profiles.where((p) => p.id == chain.profileId).firstOrNull;
    } else {
      profile = await showDialog<Profile>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(_text(context, '选择配置', 'Choose profile')),
          children: [
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_text(context, '请先导入配置', 'Import a profile first')),
              ),
            for (final item in profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Text(item.label ?? item.id),
              ),
          ],
        ),
      );
    }
    if (profile == null) {
      if (chain != null && mounted) {
        context.showSnackBar(
          _text(
            context,
            '绑定配置已删除，可导出链路或删除后重新创建',
            'The bound profile was deleted. Export the chain or recreate it.',
          ),
        );
      }
      return;
    }
    final selected = profile;
    await _perform(() async {
      final source = await globalState.patchRawConfig(
        patchConfig: globalState.config.patchClashConfig,
        profile: selected,
        includeProxyChains: false,
      );
      final catalog = await loadChainCatalog(selected.id, source);
      if (!mounted) return;
      final draft =
          chain ??
          ProxyChain(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: _text(context, '新链路', 'New chain'),
            profileId: selected.id,
            hops: const [],
          );
      final result = await Navigator.of(context).push<ProxyChain>(
        MaterialPageRoute(
          builder: (_) => ChainEditorView(
            chain: draft,
            profileLabel: selected.label ?? selected.id,
            source: source,
            catalog: catalog,
          ),
        ),
      );
      if (result != null) {
        await _writeChain(result);
      }
    });
  }

  Future<void> _export() async {
    final content = ChainStore.encode(await _load());
    await picker.saveFile(
      chainLibraryFileName,
      Uint8List.fromList(utf8.encode(content)),
    );
  }

  Future<void> _import() async {
    final selected = await picker.pickerFile();
    if (selected == null) return;
    final bytes = selected.bytes;
    if (bytes == null) {
      throw const FormatException('Unable to read chain library');
    }
    final content = utf8.decode(bytes);
    final incoming = ChainStore.decode(content);
    for (final profileId
        in incoming
            .where((chain) => chain.enabled)
            .map((chain) => chain.profileId)
            .toSet()) {
      final profile = globalState.config.profiles
          .where((p) => p.id == profileId)
          .firstOrNull;
      if (profile == null) {
        throw FormatException('Bound profile $profileId no longer exists');
      }
      final source = await globalState.patchRawConfig(
        patchConfig: globalState.config.patchClashConfig,
        profile: profile,
        includeProxyChains: false,
      );
      assembleChains(
        source,
        incoming
            .where((chain) => chain.enabled && chain.profileId == profileId)
            .toList(),
        await loadChainCatalog(profileId, source),
      );
    }
    for (final chain in incoming) {
      await _writeChain(chain);
    }
  }

  Future<void> _delete(ProxyChain chain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text(context, '删除链路？', 'Delete chain?')),
        content: Text(chain.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_text(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _writeChain(chain, delete: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: Text(_text(context, '创建链路', 'Create chain')),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _perform(_import),
            icon: const Icon(Icons.file_open_outlined),
            label: Text(_text(context, '导入', 'Import')),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _perform(_export),
            icon: const Icon(Icons.save_alt),
            label: Text(_text(context, '导出', 'Export')),
          ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      Expanded(
        child: FutureBuilder<List<ProxyChain>>(
          future: _chains,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(snapshot.error.toString()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final chains = snapshot.data!;
            if (chains.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _text(
                      context,
                      '还没有链路。创建后可在代理页面选择链路策略组。',
                      'Create a chain, then select its group on the proxies page.',
                    ),
                  ),
                ),
              );
            }
            return ListView(
              children: [
                for (final chain in chains)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(chain.name),
                          subtitle: Text(
                            '${globalState.config.profiles.where((p) => p.id == chain.profileId).firstOrNull?.label ?? chain.profileId} · ${chain.hops.length} ${_text(context, '跳', 'hops')}',
                          ),
                          onTap: _busy ? null : () => _edit(chain),
                          trailing: Switch(
                            value: chain.enabled,
                            onChanged: _busy
                                ? null
                                : (enabled) => _perform(() async {
                                    final updated = ProxyChain.fromJson({
                                      ...chain.toJson(),
                                      'enabled': enabled,
                                    });
                                    if (enabled) {
                                      final profile = globalState
                                          .config
                                          .profiles
                                          .where((p) => p.id == chain.profileId)
                                          .firstOrNull;
                                      if (profile == null) {
                                        throw const FormatException(
                                          'Bound profile no longer exists',
                                        );
                                      }
                                      final source = await globalState
                                          .patchRawConfig(
                                            patchConfig: globalState
                                                .config
                                                .patchClashConfig,
                                            profile: profile,
                                            includeProxyChains: false,
                                          );
                                      assembleChains(
                                        source,
                                        [updated],
                                        await loadChainCatalog(
                                          profile.id,
                                          source,
                                        ),
                                      );
                                    }
                                    await _writeChain(updated);
                                  }),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            Tooltip(
                              message: _text(
                                context,
                                '隐藏链路策略组',
                                'Hide chain group',
                              ),
                              child: Switch(
                                value: chain.hidden,
                                onChanged: _busy
                                    ? null
                                    : (hidden) => _perform(() async {
                                        await _writeChain(
                                          ProxyChain.fromJson({
                                            ...chain.toJson(),
                                            'hidden': hidden,
                                          }),
                                        );
                                      }),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _perform(() async {
                                      final copyName =
                                          '${chain.name} (${_text(context, '副本', 'copy')})';
                                      await _writeChain(
                                        ProxyChain.fromJson({
                                          ...chain.toJson(),
                                          'id': DateTime.now()
                                              .microsecondsSinceEpoch
                                              .toString(),
                                          'name': copyName,
                                        }),
                                      );
                                    }),
                              child: Text(_text(context, '复制', 'Duplicate')),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _perform(() => _delete(chain)),
                              child: Text(_text(context, '删除', 'Delete')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class ChainEditorView extends StatefulWidget {
  const ChainEditorView({
    super.key,
    required this.chain,
    required this.profileLabel,
    required this.source,
    required this.catalog,
  });

  final ProxyChain chain;
  final String profileLabel;
  final Map<String, dynamic> source;
  final ChainCatalog catalog;

  @override
  State<ChainEditorView> createState() => _ChainEditorViewState();
}

class _ChainEditorViewState extends State<ChainEditorView> {
  late final _name = TextEditingController(text: widget.chain.name);
  late final _hops = List<ChainTarget>.from(widget.chain.hops);
  late final _entryGroups = Set<String>.from(widget.chain.entryGroups);
  late final _externalNodes = [
    for (final node in widget.chain.externalNodes)
      Map<String, dynamic>.from(node),
  ];
  late int _limit = widget.chain.branchLimit;
  bool _saving = false;

  late final _nodes = <String, Map<String, dynamic>>{
    ...widget.catalog.nodes,
    for (final node in _externalNodes) node['name'] as String: node,
  };

  String _hopLabel(ChainTarget hop) {
    if (hop.kind == ChainTargetKind.node) {
      return _nodes[hop.id]?['name']?.toString() ?? hop.id!;
    }
    return hop.id ?? hop.config?['name']?.toString() ?? 'Endpoint';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ProxyChain get _draft => ProxyChain(
    id: widget.chain.id,
    name: _name.text.trim(),
    profileId: widget.chain.profileId,
    hops: List.from(_hops),
    entryGroups: _entryGroups.toList(),
    externalNodes: List.from(_externalNodes),
    branchLimit: _limit,
    enabled: widget.chain.enabled,
    hidden: widget.chain.hidden,
    originalAutoUpdate: widget.chain.originalAutoUpdate,
  );

  Future<void> _deleteExternalNodes() async {
    final selected = await selectNodesToDelete(
      context,
      _externalNodes,
      emptyMessage: _text(context, '未添加节点', 'No added nodes'),
      referenceMessage: _text(
        context,
        '使用这些节点的跳和前置引用也会移除。保存后生效。',
        'Hops and dialer references using these nodes will also be removed. Save to apply.',
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _externalNodes.removeWhere((node) => selected.contains(node['name']));
      _hops.removeWhere(
        (hop) => hop.kind == ChainTargetKind.node && selected.contains(hop.id),
      );
      for (final node in _externalNodes) {
        if (selected.contains(node['dialer-proxy'])) {
          node.remove('dialer-proxy');
        }
      }
      _nodes
        ..clear()
        ..addAll(widget.catalog.nodes)
        ..addAll({
          for (final node in _externalNodes) node['name'] as String: node,
        });
    });
  }

  Future<void> _addHop() async {
    while (true) {
      if (!mounted) return;
      final target = await showDialog<Object>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(_text(context, '添加一跳', 'Add hop')),
          children: [
            Builder(
              builder: (buttonContext) => SimpleDialogOption(
                onPressed: () async {
                  final method = await showNodeImportMenu(buttonContext);
                  if (context.mounted && method != null) {
                    Navigator.pop(context, method);
                  }
                },
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _text(context, '添加外部节点', 'Add external nodes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, const ChainTarget.localEndpoint({})),
              child: Text(
                _text(
                  context,
                  '本地 / 自定义 HTTP、SOCKS 端点',
                  'Local / custom HTTP or SOCKS endpoint',
                ),
              ),
            ),
            for (final entry in _nodes.entries)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, ChainTarget.node(entry.key)),
                child: Text('${entry.value['name']} · ${entry.value['type']}'),
              ),
            for (final group in widget.catalog.groups.keys)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, ChainTarget.group(group)),
                child: Text('${_text(context, '策略组', 'Group')}: $group'),
              ),
          ],
        ),
      );
      if (target == null || !mounted) return;
      if (target is NodeImportMethod) {
        final nodes = await importExternalNodes(
          context,
          method: target,
          reservedNames: {
            ...nodeNames(widget.source),
            for (final node in _nodes.values) node['name'] as String,
          },
        );
        if (nodes != null && mounted) {
          setState(() {
            _externalNodes.addAll(nodes);
            for (final node in nodes) {
              _nodes[node['name'] as String] = node;
            }
          });
        }
        continue;
      }
      final hop = target as ChainTarget;
      if (hop.kind == ChainTargetKind.localEndpoint) {
        final endpoint = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => const _EndpointDialog(),
        );
        if (endpoint != null && mounted) {
          setState(() => _hops.add(ChainTarget.localEndpoint(endpoint)));
        }
      } else {
        setState(() => _hops.add(hop));
      }
      return;
    }
  }

  Future<void> _save({bool createProfile = false}) async {
    setState(() => _saving = true);
    try {
      if (_name.text.trim().isEmpty) {
        throw const FormatException('Chain name is required');
      }
      final content = ChainStore.encode([_draft]);
      ChainStore.decode(content);
      // Validate the generated configuration through the same core as profiles.
      final generated = createProfile
          ? createChainProfileConfig(widget.source, _draft, widget.catalog)
          : assembleChains(widget.source, [_draft], widget.catalog);
      final yaml = await encodeCompactYamlTask(generated);
      if (createProfile) {
        final profile = await Profile.normal(label: _draft.name)
            .copyWith(
              useScriptOverride: false,
              selectedMap:
                  globalState.config.profiles
                      .where((profile) => profile.id == widget.chain.profileId)
                      .firstOrNull
                      ?.selectedMap ??
                  {},
            )
            .saveFileWithString(yaml);
        await seedLocalProfileProviderCaches(profile.id, generated);
        await globalState.appController.addProfile(profile);
        await globalState.appController.savePreferences();
        if (mounted) {
          context.showSnackBar(
            _text(context, '已创建本地配置', 'Local profile created'),
          );
        }
        return;
      }
      final message = await clashCore.validateConfig(yaml);
      if (message.isNotEmpty) throw FormatException(message);
      if (mounted) Navigator.pop(context, _draft);
    } catch (error) {
      if (mounted) context.showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reserved = <String>{
      for (final raw in [
        ...widget.source['proxies'] as List? ?? [],
        ...widget.source['proxy-groups'] as List? ?? [],
      ])
        (raw as Map)['name'] as String,
    };
    final preview = widget.catalog.compile(_draft, reserved);
    return Scaffold(
      appBar: AppBar(
        title: Text(proxyChainsTitle(context)),
        actions: [
          TextButton(
            onPressed:
                !_saving && preview.isValid && _name.text.trim().isNotEmpty
                ? _save
                : null,
            child: Text(_text(context, '保存', 'Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.profileLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: _text(context, '链路名称', 'Chain name'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            _text(
              context,
              '按「客户端 → 第一跳 → … → 最后一跳 → 目标」排序。前置节点或策略组保留原名，前置组实时选路；仅复制后续节点，出口组按落地节点生成选项。',
              'Order: client → first hop → … → last hop → destination. The original entry node or group is reused, following its live selection; only downstream nodes are copied, with one option per exit node.',
            ),
          ),
          for (var i = 0; i < _hops.length; i++)
            ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(_hopLabel(_hops[i])),
              subtitle: Text(switch (_hops[i].kind) {
                ChainTargetKind.node => _text(context, '节点', 'Node'),
                ChainTargetKind.group => _text(context, '策略组', 'Group'),
                ChainTargetKind.localEndpoint => _text(
                  context,
                  '代理端点',
                  'Endpoint',
                ),
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _text(context, '上移', 'Move up'),
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                            final hop = _hops.removeAt(i);
                            _hops.insert(i - 1, hop);
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: _text(context, '下移', 'Move down'),
                    onPressed: i == _hops.length - 1
                        ? null
                        : () => setState(() {
                            final hop = _hops.removeAt(i);
                            _hops.insert(i + 1, hop);
                          }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: _text(context, '移除', 'Remove'),
                    onPressed: () => setState(() => _hops.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: _hops.length >= 16 ? null : _addHop,
            icon: const Icon(Icons.add),
            label: Text(_text(context, '添加一跳', 'Add hop')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _deleteExternalNodes,
            icon: const Icon(Icons.delete_outline),
            label: Text(_text(context, '删除已添加的节点', 'Delete added nodes')),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _limit,
            decoration: InputDecoration(
              labelText: _text(context, '最大路径数', 'Maximum paths'),
            ),
            items: [
              for (final limit in {16, 64, 256, 1024, _limit}.toList()..sort())
                DropdownMenuItem(value: limit, child: Text('$limit')),
            ],
            onChanged: (limit) => setState(() => _limit = limit!),
          ),
          const SizedBox(height: 16),
          Text(
            _text(context, '加入已有策略组（可选）', 'Add to existing groups (optional)'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final raw in widget.source['proxy-groups'] as List? ?? [])
            if (raw['type'] != 'relay')
              CheckboxListTile(
                dense: true,
                title: Text(raw['name'] as String),
                value: _entryGroups.contains(raw['name']),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _entryGroups.add(raw['name'] as String);
                  } else {
                    _entryGroups.remove(raw['name']);
                  }
                }),
              ),
          for (final missing in _entryGroups.where(
            (name) => !widget.catalog.groups.containsKey(name),
          ))
            CheckboxListTile(
              title: Text('$missing (${_text(context, '已不存在', 'missing')})'),
              value: true,
              onChanged: (_) => setState(() => _entryGroups.remove(missing)),
            ),
          const Divider(),
          Text(
            '${_text(context, '路径预览', 'Path preview')}: ${preview.paths.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final diagnostic in preview.diagnostics)
            Text('${diagnostic.isError ? '⚠' : 'ⓘ'} ${diagnostic.message}'),
          for (final path in preview.paths.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${_text(context, '客户端', 'Client')} → ${path.targets.map((id) => _nodes[id]?['name'] ?? id.replaceFirst('local:', '')).join(' → ')} → ${_text(context, '目标', 'Destination')}',
              ),
            ),
          if (preview.paths.length > 20)
            Text(_text(context, '仅显示前 20 条路径', 'Showing the first 20 paths')),
          const SizedBox(height: 24),
          Text(
            _text(
              context,
              '保存会将链路写入当前配置 YAML，并关闭订阅自动更新以保留修改；删除链路会撤回对应更改。只有点击下方按钮才创建新的本地配置。',
              'Save writes the chain into this profile YAML and disables subscription auto-update to retain changes. Deleting the chain removes its additions. Only the button below creates a new local profile.',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                !_saving && preview.isValid && _name.text.trim().isNotEmpty
                ? () => _save(createProfile: true)
                : null,
            icon: const Icon(Icons.note_add_outlined),
            label: Text(
              _text(context, '从链路创建本地配置', 'Create local profile from chain'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: preview.isValid
                ? () async {
                    try {
                      final generated = createChainProfileConfig(
                        widget.source,
                        _draft,
                        widget.catalog,
                      );
                      final content = await encodeCompactYamlTask(generated);
                      await picker.saveFile(
                        '${_name.text.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.yaml',
                        Uint8List.fromList(utf8.encode(content)),
                      );
                    } catch (error) {
                      if (context.mounted) {
                        context.showSnackBar(error.toString());
                      }
                    }
                  }
                : null,
            icon: const Icon(Icons.save_alt),
            label: Text(
              _text(context, '导出生成配置 YAML', 'Export generated config as YAML'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointDialog extends StatefulWidget {
  const _EndpointDialog();

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  final _name = TextEditingController(text: 'Local proxy');
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '1080');
  final _user = TextEditingController();
  final _password = TextEditingController();
  String _type = 'socks5';
  bool _tls = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [_name, _host, _port, _user, _password]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_text(context, '代理端点', 'Proxy endpoint')),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: _text(context, '名称', 'Name'),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: const [
                DropdownMenuItem(value: 'socks5', child: Text('SOCKS5')),
                DropdownMenuItem(value: 'http', child: Text('HTTP(S)')),
              ],
              onChanged: (type) => setState(() => _type = type!),
            ),
            TextField(
              controller: _host,
              decoration: InputDecoration(
                labelText: _text(context, '地址', 'Host'),
              ),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _text(context, '端口', 'Port'),
              ),
            ),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                labelText: _text(context, '用户名（可选）', 'Username (optional)'),
              ),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _text(context, '密码（可选）', 'Password (optional)'),
              ),
            ),
            if (_type == 'http')
              SwitchListTile(
                title: const Text('TLS / HTTPS'),
                value: _tls,
                onChanged: (value) => setState(() => _tls = value),
              ),
            if (system.isAndroid)
              Text(
                _text(
                  context,
                  'Android 的 127.0.0.1 指本机；另一个 VPN 应用通常不能与 Bettbox VPN 同时运行。',
                  'On Android, 127.0.0.1 means this device. Another VPN app generally cannot run alongside Bettbox VPN.',
                ),
              ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_text(context, '取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: () {
          final port = int.tryParse(_port.text);
          if (_name.text.trim().isEmpty ||
              _host.text.trim().isEmpty ||
              port == null ||
              port < 1 ||
              port > 65535) {
            setState(
              () => _error = _text(
                context,
                '请填写名称、地址和有效端口（1–65535）',
                'Enter a name, host and valid port (1–65535)',
              ),
            );
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            'name': _name.text.trim(),
            'type': _type,
            'server': _host.text.trim(),
            'port': port,
            'udp': true,
            if (_type == 'http') 'tls': _tls,
            if (_user.text.isNotEmpty) 'username': _user.text,
            if (_password.text.isNotEmpty) 'password': _password.text,
          });
        },
        child: Text(_text(context, '添加', 'Add')),
      ),
    ],
  );
}
