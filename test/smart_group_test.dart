import 'dart:convert';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/state.dart' show resolveProxyCardState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testUrl = 'https://example.com/generate_204';

  List<Group> groupsWithSelection(String now) => buildGroups(
    jsonEncode({
      'names': ['Smart', 'DIRECT'],
      'types': ['Smart', 'Direct'],
      'groups': [
        {
          'name': 'Main',
          'type': 'Selector',
          'now': 'Smart',
          'all': [0],
        },
        {
          'name': 'Smart',
          'type': 'Smart',
          'now': now,
          'testUrl': testUrl,
          'all': [1],
        },
      ],
    }),
  );

  test('compact core payload includes Smart and its automatic selection', () {
    final groups = groupsWithSelection('Smart - Select');
    final smart = groups.last;
    expect(smart.type, GroupType.Smart);
    expect(smart.type.isComputedSelected, isTrue);
    expect(smart.all.single.name, 'DIRECT');
    expect(Group.fromJson(jsonDecode(jsonEncode(smart))), smart);
    expect(groups.first.all.single.now, 'Smart - Select');

    for (final name in ['Smart', 'Main']) {
      final state = resolveProxyCardState(groups, {
        'Smart': 'DIRECT',
      }, ProxyCardState(proxyName: name));
      expect(state.proxyName, 'Smart');
      expect(state.testUrl, testUrl);
    }
  });

  test(
    'fixed Smart delay resolves to the node and uses the group test URL',
    () {
      final state = resolveProxyCardState(
        groupsWithSelection('DIRECT'),
        {},
        const ProxyCardState(proxyName: 'Smart'),
      );
      expect(state.proxyName, 'DIRECT');
      expect(state.testUrl, testUrl);
    },
  );

  test('Smart profile groups accept the YAML type smart', () {
    final group = ProxyGroup.fromJson({
      'name': 'Smart',
      'type': 'smart',
      'proxies': ['DIRECT'],
    });
    expect(group.type, GroupType.Smart);
    expect(group.toJson()['type'], 'Smart');
  });
}
