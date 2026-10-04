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

const testUrl = 'https://example.com/generate_204';
const nodeA = Proxy(name: 'A', type: 'Shadowsocks');
const nodeB = Proxy(name: 'B', type: 'Shadowsocks');

class DelayCore implements ClashHandlerInterface {
  final tests = <String>[];
  final selections = <ChangeProxyParams>[];
  bool fail = false;

  @override
  Future<String> changeProxy(ChangeProxyParams params) async {
    selections.add(params);
    return '';
  }

  @override
  Future<String> asyncTestDelay(String url, String proxyName) async {
    tests.add(proxyName);
    if (fail) throw StateError('network failure');
    return jsonEncode({'name': proxyName, 'url': url, 'value': 80});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayController implements AppController {
  List<Group> groups;
  final selected = <String, String>{};
  final delays = <Delay>[];

  DelayController(this.groups);

  @override
  List<Group> getCurrentGroups() => groups;

  @override
  ProxyCardState getProxyCardState(String name) =>
      resolveProxyCardState(groups, selected, ProxyCardState(proxyName: name));

  @override
  String getRealTestUrl(String? url) =>
      url?.isNotEmpty == true ? url! : testUrl;

  @override
  void setDelay(Delay delay) => delays.add(delay);

  @override
  dynamic addSortNum() => 0;

  @override
  void updateCurrentSelectedMap(String groupName, String proxyName) {
    selected[groupName] = proxyName;
  }

  @override
  Future<void> updateGroups({
    List<ExternalProvider>? preloadedProviders,
  }) async {
    groups = groups
        .map(
          (group) => selected[group.name] == ''
              ? group.copyWith(now: 'Smart - Select')
              : group,
        )
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  ClashCore(handler: DelayCore());
  late DelayCore core;
  late DelayController controller;
  late ClashHandlerInterface previousInterface;
  late bool previousInit;
  AppController? previousController;

  setUp(() {
    core = DelayCore();
    controller = DelayController([
      Group(
        name: 'Smart',
        type: GroupType.Smart,
        now: 'Smart - Select',
        testUrl: testUrl,
        all: [nodeA, nodeB],
      ),
      Group(
        name: 'Selector',
        type: GroupType.Selector,
        now: 'Smart',
        all: const [Proxy(name: 'Smart', type: 'Smart')],
      ),
    ]);
    previousInit = globalState.isInit;
    previousController = previousInit ? globalState.appController : null;
    previousInterface = clashCore.clashInterface;
    globalState.appController = controller;
    clashCore.clashInterface = core;
  });

  tearDown(() {
    clashCore.clashInterface = previousInterface;
    if (previousController != null) {
      globalState.appController = previousController!;
    }
    globalState.isInit = previousInit;
  });

  test(
    'Smart group test checks all members and restores automatic selection',
    () async {
      controller.groups[0] = controller.groups[0].copyWith(now: 'A');
      controller.selected['Smart'] = 'A';
      // Even if the visible list is filtered, the Smart header tests all members.
      await delayTest([nodeA], testUrl: testUrl, groupName: 'Smart');
      expect(core.tests, unorderedEquals(['A', 'B']));
      expect(core.selections, hasLength(1));
      expect(core.selections.single.groupName, 'Smart');
      expect(core.selections.single.proxyName, '');
      expect(controller.selected['Smart'], '');
      expect(delayTestCoordinator.isTesting, isFalse);
    },
  );

  test(
    'another group probes Smart once without resetting its selection',
    () async {
      await delayTest(
        const [Proxy(name: 'Smart', type: 'Smart')],
        testUrl: testUrl,
        groupName: 'Selector',
      );
      expect(core.tests, ['Smart']);
      expect(core.selections, isEmpty);
      expect(controller.delays.last.value, 80);
    },
  );

  test('single Smart card respects a fixed node', () async {
    controller.groups[0] = controller.groups[0].copyWith(now: 'B');
    await proxyDelayTest(const Proxy(name: 'Smart', type: 'Smart'), testUrl);
    expect(core.tests, ['B']);
    expect(core.selections, isEmpty);
  });

  test('failed Smart probe clears its spinner and can be retried', () async {
    core.fail = true;
    await expectLater(
      proxyDelayTest(const Proxy(name: 'Smart', type: 'Smart'), testUrl),
      throwsStateError,
    );
    expect(controller.delays.first.value, 0);
    expect(
      controller.delays.last,
      const Delay(name: 'Smart', url: testUrl, value: -1),
    );
    core.fail = false;
    await proxyDelayTest(const Proxy(name: 'Smart', type: 'Smart'), testUrl);
    expect(controller.delays.last.value, 80);
  });
}
