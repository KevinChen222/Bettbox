import 'package:bett_box/clash/core.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/pages/editor.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/material.dart';

import 'menu.dart';
import 'nodes.dart';

Future<List<Map<String, dynamic>>?> importExternalNodes(
  BuildContext context, {
  required Set<String> reservedNames,
  NodeImportMethod? method,
}) async {
  method ??= await showNodeImportMenu(context);
  if (method == null || !context.mounted) return null;
  final nodes = method == NodeImportMethod.manual
      ? await Navigator.of(context).push<List<Map<String, dynamic>>>(
          MaterialPageRoute(builder: (_) => const _ManualNodeEditor()),
        )
      : await showDialog<List<Map<String, dynamic>>>(
          context: context,
          builder: (_) => const _SubscriptionNodeDialog(),
        );
  if (nodes == null) return null;
  return allocateImportedNodeNames(nodes, reservedNames);
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
  const _SubscriptionNodeDialog();

  @override
  State<_SubscriptionNodeDialog> createState() =>
      _SubscriptionNodeDialogState();
}

class _SubscriptionNodeDialogState extends State<_SubscriptionNodeDialog> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
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
      final response = await request
          .getTextResponseForUrl(uri.toString())
          .timeout(const Duration(seconds: 30));
      final nodes = await clashCore.importNodes(response.data as String);
      if (mounted) Navigator.pop(context, nodes);
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              nodeImportText(
                context,
                '仅导入订阅中的节点，不导入规则或策略组，也不会自动更新此链接。',
                'Import nodes only, without rules or groups. This URL will not be updated automatically.',
              ),
            ),
            const SizedBox(height: 16),
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
