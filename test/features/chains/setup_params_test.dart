import 'dart:convert';
import 'dart:io';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/clash/interface.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/features/chains/compiler.dart';
import 'package:bett_box/features/chains/integration.dart';
import 'package:bett_box/features/chains/model.dart';
import 'package:bett_box/features/chains/store.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class SetupPaths extends PathProviderPlatform {
  SetupPaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getTemporaryPath() async => root;
  @override
  Future<String> getDownloadsPath() async => root;
}

class PreviewCore implements ClashHandlerInterface {
  String runtime = '';
  final previews = <SetupParams>[];
  Map<String, dynamic>? exportedInput;

  @override
  Future<Result> getRuntimeConfig(SetupParams params) async {
    previews.add(params);
    if (params.scriptedConfig.isNotEmpty) {
      final file = File(params.scriptedConfig);
      exportedInput = jsonDecode(await file.readAsString());
      await file.delete(); // Native preview consumes relay files.
    }
    return Result.success(runtime);
  }

  @override
  Future<Result> exportConfig(
    String path,
    String output, {
    String? ageSecretKey,
  }) async {
    await File(
      output,
    ).writeAsString(jsonEncode(loadYaml(await File(path).readAsString())));
    return Result.success('');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late PreviewCore core;
  const profile = Profile(
    id: 'chain-setup',
    url: 'https://example.invalid/profile',
    autoUpdateDuration: Duration(hours: 1),
  );
  const base = '''
proxies:
  - {name: entry, type: socks5, server: 127.0.0.1, port: 1080}
  - {name: exit, type: socks5, server: 127.0.0.1, port: 1081}
proxy-groups:
  - {name: choice, type: select, proxies: [entry, exit]}
rules: [MATCH,choice]
''';

  setUpAll(() async {
    home = await Directory.systemTemp.createTemp('bettbox_chain_setup_');
    PathProviderPlatform.instance = SetupPaths(home.path);
    ClashCore(handler: PreviewCore());
  });

  tearDownAll(() => home.delete(recursive: true));

  setUp(() async {
    final previous = clashCore.clashInterface;
    core = PreviewCore()..runtime = base;
    clashCore.clashInterface = core;
    addTearDown(() => clashCore.clashInterface = previous);
    globalState.config = Config(
      themeProps: defaultThemeProps,
      profiles: [profile],
      currentProfileId: profile.id,
    );
    final file = File(await appPath.getProfilePath(profile.id));
    await file.parent.create(recursive: true);
    await file.writeAsString(base);
    await (await getChainStore()).restore(ChainStore.encode([]), replace: true);
  });

  test('ordinary profiles retain the upstream path-based setup', () async {
    final params = await globalState.buildSetupParams(
      patchConfig: defaultClashConfig,
    );
    expect(core.previews, isEmpty);
    expect(params.scriptedConfig, isEmpty);
    expect(params.patch!.containsKey('chain-proxies'), isFalse);
    expect(params.profilePath, await appPath.getProfilePath(profile.id));
  });

  test(
    'chains compile after native patching and replace only nodes/groups',
    () async {
      await (await getChainStore()).put(
        const ProxyChain(
          id: 'route',
          name: 'route',
          profileId: 'chain-setup',
          hops: [ChainTarget.group('choice'), ChainTarget.node('exit')],
        ),
      );
      // Emulate the upstream patcher's updated server/filter result.
      core.runtime = base.replaceFirst('port: 1081', 'port: 2081');
      final params = await globalState.buildSetupParams(
        patchConfig: defaultClashConfig,
      );
      expect(core.previews, hasLength(1));
      expect(core.previews.single.patch!.containsKey('chain-proxies'), isFalse);
      final nodes = params.patch!['chain-proxies'] as List;
      expect(nodes.last['port'], 2081);
      expect(nodes.last['dialer-proxy'], 'choice');
      expect((params.patch!['chain-groups'] as List).last['name'], 'route');
      expect(
        params.patch!['prepend-rules'],
        core.previews.single.patch!['prepend-rules'],
      );
      expect(params.patch!['select-global'], isTrue);
      expect(params.profilePath, core.previews.single.profilePath);
    },
  );

  test(
    'persisted dangling chains are isolated even without a library entry',
    () async {
      const persisted = '''
proxies:
  - {name: path, type: socks5, server: 127.0.0.1, port: 1080, dialer-proxy: missing, x-bettbox-chain-id: route}
proxy-groups:
  - {name: route, type: select, proxies: [path], x-bettbox-chain-id: route}
rules: [MATCH,route]
''';
      await File(
        await appPath.getProfilePath(profile.id),
      ).writeAsString(persisted);
      core.runtime = persisted;
      final params = await globalState.buildSetupParams(
        patchConfig: defaultClashConfig,
      );
      expect((params.patch!['chain-proxies'] as List).single['type'], 'reject');
      expect((params.patch!['chain-groups'] as List).single['proxies'], [
        'REJECT',
      ]);
    },
  );

  test('chain editor strips managed entries before native patching', () async {
    final file = File(await appPath.getProfilePath(profile.id));
    await file.writeAsString('''
proxies:
  - {name: entry, type: socks5, server: 127.0.0.1, port: 1080}
  - {name: path, type: socks5, server: 127.0.0.1, port: 1081, x-bettbox-chain-id: route}
proxy-groups:
  - {name: choice, type: select, proxies: [entry, route]}
  - {name: route, type: select, proxies: [path], x-bettbox-chain-id: route}
''');
    await globalState.patchRawConfig(
      patchConfig: defaultClashConfig,
      includeProxyChains: false,
    );
    expect((core.exportedInput!['proxies'] as List).single['name'], 'entry');
    expect((core.exportedInput!['proxy-groups'] as List).single['proxies'], [
      'entry',
    ]);
    expect(core.previews.single.patch!.containsKey('chain-groups'), isFalse);
  });
}
