import 'dart:convert';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/clash/interface.dart';
import 'package:bett_box/controller.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/state.dart' show resolveProxyCardState;
import 'package:bett_box/state.dart';
import 'package:bett_box/views/proxies/common.dart';
import 'package:flutter_test/flutter_test.dart';

const _testUrl = 'https://example.com/generate_204';
const _nodeA = Proxy(name: 'A', type: 'Shadowsocks');
const _nodeB = Proxy(name: 'B', type: 'Shadowsocks');
const _smart = Proxy(name: 'Smart', type: 'Smart');

class _DelayCore implements ClashHandlerInterface {
  final targets = <String>[];
  final selections = <ChangeProxyParams>[];
  bool fail = false;
  String selectionError = '';

  @override
  Future<String> changeProxy(ChangeProxyParams params) async {
    selections.add(params);
    return selectionError;
  }

  @override
  Future<String> asyncTestDelays(String params, Duration timeout) async {
    final data = jsonDecode(params) as Map<String, dynamic>;
    final batch = (data['targets'] as List).cast<Map<String, dynamic>>();
    targets.addAll(batch.map((target) => target['name'] as String));
    if (fail) throw StateError('probe failed');
    return jsonEncode([
      for (final target in batch) {...target, 'value': 80},
    ]);
  }

  @override
  Future<String> asyncTestDelay(String url, String name) async {
    targets.add(name);
    if (fail) throw StateError('probe failed');
    return jsonEncode({'name': name, 'url': url, 'value': 80});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayController implements AppController {
  final List<Group> groups;
  final selected = <String, String>{};
  final delays = <Delay>[];

  _DelayController(this.groups);

  @override
  List<Group> getCurrentGroups() => List.of(groups);

  @override
  ProxyCardState getProxyCardState(String name) => resolveProxyCardState(
    getCurrentGroups(),
    selected,
    ProxyCardState(proxyName: name),
  );

  @override
  String getRealTestUrl(String? url) =>
      url?.isNotEmpty == true ? url! : _testUrl;

  @override
  void setDelay(Delay delay) => delays.add(delay);

  @override
  void addLog(Log log) {}

  @override
  dynamic addSortNum() => 0;

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {
    selected[groupName] = proxyName;
  }

  @override
  Future<void> updateGroups() async {
    if (selected['Smart'] == '') {
      groups[0] = groups[0].copyWith(now: 'Smart - Select');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ClashCore(handler: _DelayCore());
  late _DelayCore core;
  late _DelayController controller;

  void fixSelectionOnB() {
    controller.groups[0] = controller.groups[0].copyWith(now: 'B');
    controller.selected['Smart'] = 'B';
  }

  setUp(() {
    core = _DelayCore();
    controller = _DelayController([
      const Group(
        name: 'Smart',
        type: GroupType.Smart,
        now: 'Smart - Select',
        testUrl: _testUrl,
        all: [
          _nodeA,
          _nodeB,
          Proxy(name: 'REJECT', type: 'Reject'),
        ],
      ),
      const Group(
        name: 'Main',
        type: GroupType.Selector,
        now: 'Smart',
        all: [_smart],
      ),
    ]);
    globalState.appController = controller;
    clashCore.clashInterface = core;
  });

  test(
    'Smart group test resets selection and batches all testable members',
    () async {
      fixSelectionOnB();
      await delayTest([_nodeA], groupName: 'Smart', testUrl: _testUrl);
      expect(core.selections, [
        const ChangeProxyParams(groupName: 'Smart', proxyName: ''),
      ]);
      expect(controller.selected['Smart'], '');
      expect(core.targets, unorderedEquals(['A', 'B']));
      expect(delayTestCoordinator.isTesting, isFalse);
    },
  );

  test(
    'a parent group probes auto Smart once and follows fixed Smart',
    () async {
      await delayTest([_smart], groupName: 'Main', testUrl: _testUrl);
      fixSelectionOnB();
      await delayTest([_smart], groupName: 'Main', testUrl: _testUrl);
      expect(core.targets, ['Smart', 'B']);
      expect(core.selections, isEmpty);
      expect(controller.selected['Smart'], 'B');
    },
  );

  test(
    'a failed Smart reset keeps the fixed node and sends no probes',
    () async {
      fixSelectionOnB();
      core.selectionError = 'reset failed';
      await expectLater(
        delayTest([_nodeA], groupName: 'Smart'),
        throwsStateError,
      );
      expect(core.targets, isEmpty);
      expect(controller.selected['Smart'], 'B');
      expect(delayTestCoordinator.isTesting, isFalse);
    },
  );

  test(
    'a failed Smart batch clears the pending delays and allows retry',
    () async {
      core.fail = true;
      await delayTest([_nodeA], groupName: 'Smart', testUrl: _testUrl);
      for (final name in ['A', 'B']) {
        expect(
          controller.delays.lastWhere((delay) => delay.name == name).value,
          -1,
        );
      }
      expect(delayTestCoordinator.isTesting, isFalse);
      core.fail = false;
      await delayTest([_nodeA], groupName: 'Smart', testUrl: _testUrl);
      expect(core.targets, unorderedEquals(['A', 'B', 'A', 'B']));
      expect(controller.delays.last.value, 80);
    },
  );

  test(
    'single Smart probe clears failed delay and follows a fixed node',
    () async {
      core.fail = true;
      await expectLater(proxyDelayTest(_smart), throwsStateError);
      expect(
        controller.delays.last,
        const Delay(name: 'Smart', url: _testUrl, value: -1),
      );
      core.fail = false;
      fixSelectionOnB();
      await proxyDelayTest(_smart);
      expect(core.targets, ['Smart', 'B']);
      expect(core.selections, isEmpty);
    },
  );
}
