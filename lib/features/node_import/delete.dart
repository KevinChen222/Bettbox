import 'package:bett_box/common/common.dart';
import 'package:flutter/material.dart';

import 'menu.dart';

class NodeDeletion {
  const NodeDeletion({required this.nodes, required this.subscriptions});
  final Set<String> nodes;
  final Set<String> subscriptions;
}

Future<NodeDeletion?> selectNodesToDelete(
  BuildContext context,
  List<Map<String, dynamic>> nodes, {
  String? emptyMessage,
  Map<String, List<String>> subscriptions = const {},
  required String referenceMessage,
}) async {
  if (nodes.isEmpty && subscriptions.isEmpty) {
    context.showSnackBar(
      emptyMessage ?? nodeImportText(context, '没有可删除的节点', 'No nodes to delete'),
    );
    return null;
  }
  final selected = <String>{};
  final selectedSubscriptions = <String>{};
  Set<String> subscriptionNodes() => {
    for (final name in selectedSubscriptions) ...subscriptions[name]!,
  };
  final result = await showDialog<NodeDeletion>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          nodeImportText(
            context,
            '选择要删除的订阅或节点',
            'Select subscriptions or nodes to delete',
          ),
        ),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final name in subscriptions.keys)
                CheckboxListTile(
                  title: Text(name),
                  subtitle: Text(nodeImportText(context, '订阅', 'Subscription')),
                  value: selectedSubscriptions.contains(name),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      selectedSubscriptions.add(name);
                    } else {
                      selectedSubscriptions.remove(name);
                    }
                  }),
                ),
              if (subscriptions.isNotEmpty && nodes.isNotEmpty) const Divider(),
              for (final node in nodes)
                CheckboxListTile(
                  title: Text(node['name'] as String),
                  subtitle: Text(node['type']?.toString() ?? ''),
                  value:
                      selected.contains(node['name']) ||
                      subscriptionNodes().contains(node['name']),
                  onChanged: subscriptionNodes().contains(node['name'])
                      ? null
                      : (checked) => setState(() {
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
            onPressed: selected.isEmpty && selectedSubscriptions.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    NodeDeletion(
                      nodes: {...selected, ...subscriptionNodes()},
                      subscriptions: {...selectedSubscriptions},
                    ),
                  ),
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
          '确认删除 ${result.subscriptions.length} 个订阅、${result.nodes.length} 个节点？',
          'Delete ${result.subscriptions.length} subscriptions and ${result.nodes.length} nodes?',
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          '${[...result.subscriptions, ...result.nodes].join('\n')}\n\n$referenceMessage',
        ),
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
