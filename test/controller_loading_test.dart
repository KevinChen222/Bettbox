import 'dart:async';
import 'dart:convert';

import 'package:bett_box/clash/interface.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/controller.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter/widgets.dart' show Brightness, Size, SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingConfigCore extends ClashHandlerInterface {
  late Action pending;

  @override
  void sendMessage(String message) {
    pending = Action.fromJson(jsonDecode(message));
  }

  Future<void> finish() => handleResult(
    ActionResult(id: pending.id, method: pending.method, data: ''),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final timeout in [false, true]) {
    testWidgets(
      'configuration ${timeout ? 'timeout' : 'success'} clears loading',
      (tester) async {
        globalState.appState = AppState(
          brightness: Brightness.light,
          version: 1,
          viewSize: Size.zero,
          requests: FixedList(1),
          logs: FixedList(1),
          traffics: FixedList(1),
          totalTraffic: Traffic(),
          systemUiOverlayStyle: const SystemUiOverlayStyle(),
        );
        late AppController controller;
        late WidgetRef ref;
        await tester.pumpWidget(
          ProviderScope(
            child: Consumer(
              builder: (context, widgetRef, _) {
                widgetRef.watch(loadingProvider);
                ref = widgetRef;
                controller = AppController(context, widgetRef);
                return const SizedBox();
              },
            ),
          ),
        );
        final core = PendingConfigCore();
        final result = controller.safeRun(
          () => core.invoke<String>(
            method: ActionMethod.setupConfig,
            timeout: const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('setupConfig timeout'),
          ),
          needLoading: true,
        );
        await tester.pump();
        expect(ref.read(loadingProvider), isTrue);
        if (timeout) {
          await tester.pump(const Duration(seconds: 15));
          expect(await result, isNull);
        } else {
          await core.finish();
          await tester.pump();
          expect(await result, '');
        }
        expect(ref.read(loadingProvider), isFalse);
        await tester.pump(const Duration(seconds: 16));
        // A timed-out native action may finish later; it must not restore loading.
        if (timeout) await core.finish();
        expect(ref.read(loadingProvider), isFalse);
        expect(core.callbackCompleterMap, isEmpty);
      },
    );
  }
}
