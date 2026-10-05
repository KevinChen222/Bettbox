import 'package:bett_box/common/common.dart';
import 'package:flutter/material.dart';

import 'menu.dart';

Future<Set<String>?> selectNodesToDelete(
  BuildContext context,
  List<Map<String, dynamic>> nodes, {
  String? emptyMessage,
  required String referenceMessage,
}) async {
  if (nodes.isEmpty) {
    context.showSnackBar(
      emptyMessage ?? nodeImportText(context, '没有可删除的节点', 'No nodes to delete'),
    );
    return null;
  }
  final selected = <String>{};
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          nodeImportText(context, '选择要删除的节点', 'Select nodes to delete'),
        ),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final node in nodes)
                CheckboxListTile(
                  title: Text(node['name'] as String),
                  subtitle: Text(node['type']?.toString() ?? ''),
                  value: selected.contains(node['name']),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      selected.add(node['name'] as String);
                    } else {
                      selected.remove(node['name']);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(nodeImportText(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.pop(context, selected),
            child: Text(nodeImportText(context, '删除', 'Delete')),
          ),
        ],
      ),
    ),
  );
  if (result == null || !context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        nodeImportText(
          context,
          '确认删除 ${result.length} 个节点？',
          'Delete ${result.length} nodes?',
        ),
      ),
      content: SingleChildScrollView(
        child: Text('${result.join('\n')}\n\n$referenceMessage'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(nodeImportText(context, '取消', 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(nodeImportText(context, '删除', 'Delete')),
        ),
      ],
    ),
  );
  return confirmed == true ? result : null;
}
