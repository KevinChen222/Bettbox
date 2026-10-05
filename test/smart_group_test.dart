import 'package:bett_box/common/utils.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/state.dart' show resolveProxyCardState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testUrl = 'https://example.com/generate_204';
  final smart = Group(
    name: 'Smart',
    type: GroupType.Smart,
    now: 'Smart - Select',
    testUrl: testUrl,
    all: const [Proxy(name: 'DIRECT', type: 'Direct')],
  );

  test('automatic Smart delay targets the group, not its virtual now', () {
    final state = resolveProxyCardState(
      [smart],
      {},
      const ProxyCardState(proxyName: 'Smart'),
    );
    expect(state.proxyName, 'Smart');
    expect(state.testUrl, testUrl);
  });

  test('Smart nested in a Selector remains one test target', () {
    final selector = Group(
      name: 'Selector',
      type: GroupType.Selector,
      now: 'Smart',
      all: const [Proxy(name: 'Smart', type: 'Smart')],
    );
    final state = resolveProxyCardState(
      [selector, smart],
      {},
      const ProxyCardState(proxyName: 'Selector'),
    );
    expect(state.proxyName, 'Smart');
    expect(state.testUrl, testUrl);
  });

  test('fixed Smart delay follows only the fixed node', () {
    final state = resolveProxyCardState(
      [smart.copyWith(now: 'DIRECT')],
      {},
      const ProxyCardState(proxyName: 'Smart'),
    );
    expect(state.proxyName, 'DIRECT');
    expect(state.testUrl, testUrl);
  });

  test('Smart release tags compare the Bettbox application version', () {
    final utils = Utils();
    expect(utils.compareVersions('smart-v1.19.5-20261004.1', '1.19.4'), 1);
    expect(utils.compareVersions('smart-v1.19.4-20261004.1', '1.19.4'), 0);
    expect(utils.compareVersions('v1.19.5', '1.19.4'), 1);
  });

  test('Smart updates compare release builds without offering a downgrade', () {
    final utils = Utils();
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.4-20261005.1',
        '1.19.4',
        '2026100101',
      ),
      isTrue,
    );
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.4-20261005.1',
        '1.19.4',
        '2026100501',
      ),
      isFalse,
    );
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.4-20261004.3',
        '1.19.4',
        '2026100501',
      ),
      isFalse,
    );
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.4-20261005.2',
        '1.19.4',
        '2026100501',
      ),
      isTrue,
    );
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.5-20261004.1',
        '1.19.4',
        '2026100501',
      ),
      isTrue,
    );
    expect(
      utils.hasReleaseUpdate(
        'smart-v1.19.3-20261006.1',
        '1.19.4',
        '2026100501',
      ),
      isFalse,
    );
  });

  test('Smart profile group is accepted', () {
    final group = ProxyGroup.fromJson({
      'name': 'Smart',
      'type': 'smart',
      'proxies': ['DIRECT'],
    });
    expect(group.type, GroupType.Smart);
  });

  test('Smart core JSON is visible and supports automatic selection', () {
    final group = Group.fromJson({
      'name': 'Smart',
      'type': 'Smart',
      'now': 'Smart - Select',
      'all': [
        {'name': 'DIRECT', 'type': 'Direct'},
      ],
    });
    expect(GroupTypeExtension.valueList, contains('Smart'));
    expect(group.type.isComputedSelected, isTrue);
    expect(group.all.single.name, 'DIRECT');
    expect(group.toJson()['type'], 'Smart');
  });
}
