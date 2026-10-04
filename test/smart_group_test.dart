import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
