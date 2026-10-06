import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/pages/editor.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/material.dart';

import 'menu.dart';
import 'nodes.dart';

class ImportedNodes {
  const ImportedNodes(this.nodes, {this.subscriptionName});
  final List<Map<String, dynamic>> nodes;
  final String? subscriptionName;
}

class SubscriptionImport {
  const SubscriptionImport({
    required this.url,
    this.name,
    this.nodes = const [],
  });
  final String url;
  final String? name;
  final List<Map<String, dynamic>> nodes;
}

Future<SubscriptionImport?> showSubscriptionImport(
  BuildContext context, {
  bool provider = false,
}) => showDialog<SubscriptionImport>(
  context: context,
  builder: (_) => _SubscriptionNodeDialog(provider: provider),
);

Future<ImportedNodes?> importExternalNodes(
  BuildContext context, {
  required Set<String> reservedNames,
  NodeImportMethod? method,
}) async {
  method ??= await showNodeImportMenu(context);
  if (method == null || !context.mounted) return null;
  if (method == NodeImportMethod.manual) {
    final nodes = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(builder: (_) => const _ManualNodeEditor()),
    );
    return nodes == null
        ? null
        : ImportedNodes(allocateImportedNodeNames(nodes, reservedNames));
  }
  final subscription = await showSubscriptionImport(context);
  return subscription == null
      ? null
      : ImportedNodes(
          allocateImportedNodeNames(subscription.nodes, reservedNames),
          subscriptionName: subscription.name ?? '',
        );
}

class _ManualNodeEditor extends StatefulWidget {
  const _ManualNodeEditor();

  @override
  State<_ManualNodeEditor> createState() => _ManualNodeEditorState();
}

class _ManualNodeEditorState extends State<_ManualNodeEditor> {
  bool _busy = false;

  Future<void> _add(BuildContext editorContext, String content) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final nodes = await clashCore.importNodes(content);
      if (editorContext.mounted) Navigator.pop(editorContext, nodes);
    } catch (error) {
      if (editorContext.mounted) editorContext.showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AbsorbPointer(
        absorbing: _busy,
        child: EditorPage(
          title: nodeImportText(context, '手动添加节点', 'Add nodes manually'),
          content: '',
          onSave: (context, _, content) => _add(context, content),
          onPop: (context, _, content) async {
            if (_busy) return false;
            if (content.trim().isEmpty) return true;
            final save = await globalState.showMessage(
              title: appLocalizations.tip,
              message: TextSpan(text: appLocalizations.hasCacheChange),
            );
            if (save == true && context.mounted) {
              await _add(context, content);
              return false;
            }
            return true;
          },
        ),
      ),
      if (_busy)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0x66000000),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ],
  );
}

class _SubscriptionNodeDialog extends StatefulWidget {
  const _SubscriptionNodeDialog({required this.provider});

  final bool provider;

  @override
  State<_SubscriptionNodeDialog> createState() =>
      _SubscriptionNodeDialogState();
}

class _SubscriptionNodeDialogState extends State<_SubscriptionNodeDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(
        () => _error = nodeImportText(
          context,
          '请输入有效的 HTTP(S) 订阅链接',
          'Enter a valid HTTP(S) subscription URL',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var name = _name.text.trim();
      var nodes = <Map<String, dynamic>>[];
      if (!widget.provider || name.isEmpty) {
        final response = await request
            .getTextResponseForUrl(uri.toString())
            .timeout(const Duration(seconds: 30));
        if (name.isEmpty) {
          name = subscriptionNameFromHeaders(response.headers.map) ?? '';
        }
        if (!widget.provider) {
          nodes = await clashCore.importNodes(response.data as String);
        }
      }
      if (mounted) {
        Navigator.pop(
          context,
          SubscriptionImport(url: uri.toString(), name: name, nodes: nodes),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(nodeImportText(context, '订阅链接', 'Subscription URL')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                nodeImportText(
                  context,
                  widget.provider
                      ? '保存为订阅提供者，每 24 小时更新一次，可在提供者页面手动更新。'
                      : '仅导入节点，不导入规则或策略组。可按订阅整批删除，不自动更新。',
                  widget.provider
                      ? 'Save as a provider, updated every 24 hours. You can also update it on the providers page.'
                      : 'Import nodes only, without rules or groups. Delete by subscription; no automatic updates.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: nodeImportText(
                    context,
                    '订阅名称（可留空）',
                    'Subscription name (optional)',
                  ),
                  helperText: nodeImportText(
                    context,
                    '留空使用订阅返回名称，否则命名为新添加1、2…',
                    'Use the returned name, or 新添加1, 2… if unavailable',
                  ),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _url,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                onSubmitted: (_) {
                  if (!_busy) _add();
                },
                decoration: InputDecoration(
                  labelText: 'URL',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  errorMaxLines: 4,
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(appLocalizations.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: Text(appLocalizations.add),
        ),
      ],
    ),
  );
}
