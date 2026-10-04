import 'package:bett_box/common/utils.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Smart release tags compare the Bettbox application version', () {
    final utils = Utils();
    expect(utils.compareVersions('smart-v1.19.5-20261004.1', '1.19.4'), 1);
    expect(utils.compareVersions('smart-v1.19.4-20261004.1', '1.19.4'), 0);
    expect(utils.compareVersions('v1.19.5', '1.19.4'), 1);
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
