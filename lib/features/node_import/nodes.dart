import 'dart:convert';
import 'dart:io';

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

/// Replace a single section while leaving rules, providers and other text intact.
String replaceProfileSection(String content, String name, dynamic value) {
  final root = loadYamlNode(content) as YamlMap;
  final key = root.nodes.keys.where((key) => key.value == name).firstOrNull;
  if (key == null) {
    if (root.style == CollectionStyle.FLOW) {
      return content.replaceRange(
        root.span.end.offset - 1,
        root.span.end.offset - 1,
        '${root.isEmpty ? '' : ','} ${jsonEncode(name)}: ${jsonEncode(value)}',
      );
    }
    final newline = content.contains('\r\n') ? '\r\n' : '\n';
    final offset = root.span.end.offset;
    return content.replaceRange(
      offset,
      offset,
      '${offset > 0 && content[offset - 1] != '\n' ? newline : ''}$name: ${jsonEncode(value)}$newline',
    );
  }
  final section = root.nodes[name]!;
  final alias = RegExp(
    r'^\s*:\s*\*[^\s,}\]]+',
  ).firstMatch(content.substring(key.span.end.offset));
  if (alias != null) {
    return content.replaceRange(
      key.span.end.offset + alias.group(0)!.indexOf('*'),
      key.span.end.offset + alias.end,
      jsonEncode(value),
    );
  }
  if (section.span.length == 0) {
    final offset = content.indexOf(':', key.span.end.offset) + 1;
    return content.replaceRange(offset, offset, ' ${jsonEncode(value)}');
  }
  final anchor = RegExp(
    r'^&[^\s]+\s*',
  ).firstMatch(section.span.text)?.group(0)?.trim();
  // Indentless block lists are valid YAML; their flow replacements need indent.
  final indent =
      section is YamlList &&
          section.style == CollectionStyle.BLOCK &&
          section.span.start.column == key.span.start.column
      ? '  '
      : '';
  return content.replaceRange(
    section.span.start.offset,
    _sectionEnd(section),
    '$indent${anchor == null ? '' : '$anchor '}${jsonEncode(value)}',
  );
}

int _sectionEnd(YamlNode node) {
  if (node is YamlList &&
      node.style == CollectionStyle.BLOCK &&
      node.nodes.isNotEmpty) {
    return _sectionEnd(node.nodes.last);
  }
  if (node is YamlMap &&
      node.style == CollectionStyle.BLOCK &&
      node.nodes.isNotEmpty) {
    return _sectionEnd(node.nodes.values.last);
  }
  return node.span.end.offset;
}

String removeNodesFromProfile(String content, Set<String> names) {
  final config =
      jsonDecode(jsonEncode(loadYaml(content))) as Map<String, dynamic>;
  final nodes = config['proxies'] as List? ?? [];
  nodes.removeWhere((node) => names.contains(node['name']));
  for (final node in nodes) {
    if (names.contains(node['dialer-proxy'])) node.remove('dialer-proxy');
  }
  var updated = replaceProfileSection(content, 'proxies', nodes);
  final groups = config['proxy-groups'] as List?;
  var changed = false;
  for (final group in groups ?? []) {
    final members = group['proxies'] as List?;
    if (members == null || !members.any(names.contains)) continue;
    changed = true;
    members.removeWhere(names.contains);
    if (members.isEmpty &&
        group['include-all'] != true &&
        group['include-all-proxies'] != true &&
        group['include-all-providers'] != true &&
        (group['use'] as List? ?? []).isEmpty) {
      members.add('DIRECT');
    }
  }
  if (changed) updated = replaceProfileSection(updated, 'proxy-groups', groups);
  return updated;
}

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

/// Prepend without re-encoding the profile's rules, groups or comments.
String prependNodesToProfile(String content, List<Map<String, dynamic>> nodes) {
  if (nodes.isEmpty) return content;
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
      jsonEncode([...nodes, ...proxies.value as List]),
    );
  }
  final list = proxies as YamlList;
  if (list.style == CollectionStyle.FLOW) {
    final offset = content.indexOf('[', proxies.span.start.offset) + 1;
    final addition =
        '${nodes.map(jsonEncode).join(', ')}${list.isEmpty ? '' : ', '}';
    return content.replaceRange(offset, offset, addition);
  }
  final firstRow = RegExp(
    r'(^|\n)( *)-(?:[ \r\n]|$)',
  ).firstMatch(proxies.span.text)!;
  final column =
      firstRow.group(2)!.length +
      (firstRow.start == 0 ? proxies.span.start.column : 0);
  final indent = ' ' * column;
  final offset =
      proxies.span.start.offset +
      firstRow.start +
      firstRow.group(1)!.length +
      firstRow.group(2)!.length;
  final rows = nodes
      .map((node) => '- ${jsonEncode(node)}')
      .join('$newline$indent');
  return content.replaceRange(offset, offset, '$rows$newline$indent');
}

String? subscriptionNameFromHeaders(Map<String, List<String>> headers) {
  final title = headers['profile-title']?.firstOrNull;
  if (title?.isNotEmpty == true) {
    if (!title!.startsWith('base64:')) return title.trim();
    return utf8
        .decode(base64.decode(base64.normalize(title.substring(7))))
        .trim();
  }
  final disposition = headers['content-disposition']?.firstOrNull;
  if (disposition == null) return null;
  final parameters = HeaderValue.parse(disposition).parameters;
  final encoded = parameters['filename*'];
  if (encoded != null) {
    final parts = encoded.split("'");
    if (parts.length >= 3) {
      return Uri.decodeComponent(parts.skip(2).join("'")).trim();
    }
  }
  return parameters['filename']?.trim();
}

String allocateSubscriptionName(String? requested, Set<String> reserved) {
  final base = requested?.trim() ?? '';
  if (base.isEmpty) {
    var suffix = 1;
    while (reserved.contains('新添加$suffix')) {
      suffix++;
    }
    return '新添加$suffix';
  }
  var name = base;
  var suffix = 2;
  while (reserved.contains(name)) {
    name = '$base (${suffix++})';
  }
  return name;
}

Map<String, dynamic> subscriptionProvider(
  String name,
  String url,
  Map providers,
) {
  var filename = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (filename.isEmpty ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(filename)) {
    filename = 'provider_$filename';
  }
  final used = {
    for (final provider in providers.values)
      if (provider is Map && provider['path'] is String)
        (provider['path'] as String)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^\./'), '')
            .toLowerCase(),
  };
  var path = './proxies/$filename.yaml';
  var suffix = 2;
  while (used.contains(path.substring(2).toLowerCase())) {
    path = './proxies/$filename (${suffix++}).yaml';
  }
  return {
    'type': 'http',
    'url': url,
    'path': path,
    'interval': 86400,
    'health-check': {
      'enable': true,
      'url': 'https://www.gstatic.com/generate_204',
      'interval': 600,
    },
  };
}

String addProviderToProfile(
  String content,
  String name,
  Map<String, dynamic> provider,
) {
  final root = loadYamlNode(content) as YamlMap;
  final providers = root.nodes['proxy-providers'];
  final key = root.nodes.keys
      .where((key) => key.value == 'proxy-providers')
      .firstOrNull;
  if (providers is! YamlMap && providers?.value != null) {
    throw const FormatException(
      'proxy-providers 必须是对象 / proxy-providers must be a map',
    );
  }
  final merged = <String, dynamic>{
    if (providers is YamlMap) ...Map<String, dynamic>.from(providers.value),
    name: provider,
  };
  if ((providers is YamlMap && providers.containsKey(name))) {
    throw FormatException('Provider already exists: $name');
  }
  // Flow collections and aliases retain their original surrounding YAML.
  if (root.style == CollectionStyle.FLOW ||
      (providers is YamlMap && providers.style == CollectionStyle.FLOW) ||
      (key != null &&
          RegExp(
            r'^\s*:\s*\*',
          ).hasMatch(content.substring(key.span.end.offset)))) {
    return replaceProfileSection(content, 'proxy-providers', merged);
  }
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  final column = providers is YamlMap && providers.isNotEmpty
      ? providers.nodes.keys.first.span.start.column
      : (key?.span.start.column ?? root.span.start.column) + 2;
  final indent = ' ' * column;
  final rows = [
    '$indent${jsonEncode(name)}:',
    for (final entry in provider.entries)
      if (entry.value is Map) ...[
        '$indent  ${entry.key}:',
        for (final field in (entry.value as Map).entries)
          '$indent    ${field.key}: ${jsonEncode(field.value)}',
      ] else
        '$indent  ${entry.key}: ${jsonEncode(entry.value)}',
  ].join(newline);
  if (providers == null) {
    final offset = root.span.end.offset;
    return content.replaceRange(
      offset,
      offset,
      '${offset > 0 && content[offset - 1] != '\n' ? newline : ''}${' ' * root.span.start.column}proxy-providers:$newline$rows$newline',
    );
  }
  if (providers is! YamlMap || providers.isEmpty) {
    if (providers.span.length == 0) {
      final offset = content.indexOf(':', key!.span.end.offset) + 1;
      return content.replaceRange(offset, offset, '$newline$rows');
    }
    return content.replaceRange(
      providers.span.start.offset,
      providers.span.end.offset,
      '$newline$rows$newline',
    );
  }
  var offset = _sectionEnd(providers);
  if (offset < content.length && content[offset - 1] != '\n') {
    final endOfLine = content.indexOf('\n', offset);
    offset = endOfLine < 0 ? content.length : endOfLine + 1;
  }
  return content.replaceRange(
    offset,
    offset,
    '${offset > 0 && content[offset - 1] != '\n' ? newline : ''}$rows$newline',
  );
}

String removeProvidersFromProfile(String content, Set<String> names) {
  final config =
      jsonDecode(jsonEncode(loadYaml(content))) as Map<String, dynamic>;
  final providers = config['proxy-providers'] as Map? ?? {};
  providers.removeWhere((name, _) => names.contains(name));
  var updated = replaceProfileSection(content, 'proxy-providers', providers);
  final groups = config['proxy-groups'] as List? ?? [];
  var changed = false;
  for (final group in groups) {
    final uses = group['use'] as List?;
    if (uses == null || !uses.any(names.contains)) continue;
    changed = true;
    uses.removeWhere(names.contains);
    if (uses.isEmpty &&
        (group['proxies'] as List? ?? []).isEmpty &&
        group['include-all'] != true &&
        group['include-all-proxies'] != true &&
        !(group['include-all-providers'] == true && providers.isNotEmpty)) {
      group['proxies'] = ['DIRECT'];
    }
  }
  if (changed) updated = replaceProfileSection(updated, 'proxy-groups', groups);
  return updated;
}

/// Reapply only additions saved by the profile editor after a subscription refresh.
({
  String content,
  List<Map<String, dynamic>> nodes,
  Map<String, Map<String, dynamic>> providers,
})
mergeProfileAdditions(
  String content,
  List<Map<String, dynamic>> addedNodes,
  Map<String, Map<String, dynamic>> addedProviders,
) {
  final config =
      jsonDecode(jsonEncode(loadYaml(content))) as Map<String, dynamic>;
  final nodes = allocateImportedNodeNames(addedNodes, nodeNames(config));
  var updated = prependNodesToProfile(content, nodes);
  final existing = Map<String, dynamic>.from(
    config['proxy-providers'] as Map? ?? {},
  );
  final reserved = {
    ...nodeNames(config),
    ...nodes.map((node) => node['name'] as String),
    ...existing.keys,
  };
  final providers = <String, Map<String, dynamic>>{};
  for (final entry in addedProviders.entries) {
    final name = allocateSubscriptionName(entry.key, reserved);
    reserved.add(name);
    final provider = {
      ...entry.value,
      'path': subscriptionProvider(
        name,
        entry.value['url'] as String,
        existing,
      )['path'],
    };
    updated = addProviderToProfile(updated, name, provider);
    providers[name] = provider;
    existing[name] = provider;
  }
  return (content: updated, nodes: nodes, providers: providers);
}
