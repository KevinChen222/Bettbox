import 'dart:convert';

import 'package:yaml/yaml.dart';

const builtInProxyNames = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
  'GLOBAL',
};

Set<String> nodeNames(Map config) => {
  ...builtInProxyNames,
  for (final raw in [
    ...config['proxies'] as List? ?? [],
    ...config['proxy-groups'] as List? ?? [],
  ])
    (raw as Map)['name'] as String,
};

List<Map<String, dynamic>> allocateImportedNodeNames(
  List<Map<String, dynamic>> nodes,
  Set<String> reserved,
) {
  final used = {...reserved, ...nodes.map((node) => node['name'] as String)};
  final names = <String, String>{};
  for (final node in nodes) {
    final original = node['name'] as String;
    var name = original;
    if (reserved.contains(name)) {
      var suffix = 2;
      while (used.contains(name)) {
        name = '$original (${suffix++})';
      }
      used.add(name);
    }
    names[original] = name;
  }
  return [
    for (final node in nodes)
      {
        ...node,
        'name': names[node['name']],
        if (names.containsKey(node['dialer-proxy']))
          'dialer-proxy': names[node['dialer-proxy']],
      },
  ];
}

/// Append without re-encoding the profile's rules, groups or comments.
String appendNodesToProfile(String content, List<Map<String, dynamic>> nodes) {
  final root = loadYamlNode(content);
  if (root is! YamlMap) {
    throw const FormatException('配置必须是 YAML 对象 / Expected a YAML profile');
  }
  final proxies = root.nodes['proxies'];
  if (proxies is YamlScalar && proxies.value == null) {
    if (proxies.span.length == 0) {
      final key = root.nodes.keys.firstWhere((key) => key.value == 'proxies');
      final offset = content.indexOf(':', key.span.end.offset) + 1;
      return content.replaceRange(offset, offset, ' ${jsonEncode(nodes)}');
    }
    return content.replaceRange(
      proxies.span.start.offset,
      proxies.span.end.offset,
      jsonEncode(nodes),
    );
  }
  if (proxies != null && proxies is! YamlList) {
    throw const FormatException('proxies 必须是列表 / proxies must be a list');
  }
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  if (proxies == null) {
    if (root.style == CollectionStyle.FLOW) {
      final offset = root.span.end.offset - 1;
      final separator =
          root.isEmpty ||
              content
                  .substring(root.span.start.offset, offset)
                  .trimRight()
                  .endsWith(',')
          ? ''
          : ',';
      return content.replaceRange(
        offset,
        offset,
        '$separator "proxies": ${jsonEncode(nodes)}',
      );
    }
    final offset = root.span.end.offset;
    final prefix = offset > 0 && content[offset - 1] != '\n' ? newline : '';
    final rows = nodes.map((node) => '  - ${jsonEncode(node)}').join(newline);
    return content.replaceRange(
      offset,
      offset,
      '${prefix}proxies:$newline$rows$newline',
    );
  }
  final key = root.nodes.keys.firstWhere((key) => key.value == 'proxies');
  final alias = RegExp(
    r'^\s*:\s*\*[^\s,}\]]+',
  ).firstMatch(content.substring(key.span.end.offset));
  if (alias != null) {
    final start = key.span.end.offset + alias.group(0)!.indexOf('*');
    return content.replaceRange(
      start,
      key.span.end.offset + alias.end,
      jsonEncode([...proxies.value as List, ...nodes]),
    );
  }
  final list = proxies as YamlList;
  if (list.style == CollectionStyle.FLOW) {
    final offset = proxies.span.end.offset - 1;
    final separator =
        list.isEmpty ||
            content
                .substring(proxies.span.start.offset, offset)
                .trimRight()
                .endsWith(',')
        ? ''
        : ',';
    final addition = '$separator ${nodes.map(jsonEncode).join(', ')}';
    return content.replaceRange(offset, offset, addition);
  }
  var offset = proxies.span.end.offset;
  if (proxies.span.end.column != 0 && offset < content.length) {
    final endOfLine = content.indexOf('\n', offset);
    offset = endOfLine < 0 ? content.length : endOfLine + 1;
  }
  final prefix = offset > 0 && content[offset - 1] != '\n' ? newline : '';
  final firstRow = RegExp(
    r'(^|\n)( *)-(?:[ \r\n]|$)',
  ).firstMatch(proxies.span.text)!;
  final column =
      firstRow.group(2)!.length +
      (firstRow.start == 0 ? proxies.span.start.column : 0);
  final indent = ' ' * column;
  final rows = nodes
      .map((node) => '$indent- ${jsonEncode(node)}')
      .join(newline);
  return content.replaceRange(offset, offset, '$prefix$rows$newline');
}
