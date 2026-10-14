import 'dart:convert';
import 'dart:io';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/clash/interface.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class SavePaths extends PathProviderPlatform {
  SavePaths(this.root);
  final String root;

  @override
  Future<String> getApplicationSupportPath() async => root;
  @override
  Future<String> getTemporaryPath() async => root;
  @override
  Future<String> getDownloadsPath() async => root;
}

class SaveCore implements ClashHandlerInterface {
  String error = '';
  String? validatedContent;
  SetupParams? validatedSetup;

  @override
  Future<String> validateConfig(
    String data, {
    String? ageSecretKey,
    SetupParams? setup,
  }) async {
    validatedSetup = setup;
    validatedContent = setup == null
        ? data
        : await File(setup.profilePath).readAsString();
    return error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;

  setUpAll(() async {
    home = await Directory.systemTemp.createTemp('bettbox_profiles_');
    PathProviderPlatform.instance = SavePaths(home.path);
  });

  tearDownAll(() => home.delete(recursive: true));

  setUp(() {
    ClashCore(handler: SaveCore());
    globalState.config = Config(themeProps: defaultThemeProps);
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
  });

  test('an unchanged update leaves the profile file untouched', () async {
    const profile = Profile(id: 'p', autoUpdateDuration: Duration(hours: 1));
    final file = File(await appPath.getProfilePath(profile.id));
    final first = utf8.encode('proxies: []\n');
    final second = utf8.encode('proxies: []\nrules: []\n');

    await profile.saveFile(first, validate: false);
    final stamp = DateTime(2020);
    await file.setLastModified(stamp);

    await profile.saveFile(first, validate: false);
    expect(await file.lastModified(), stamp);

    await profile.saveFile(second, validate: false);
    expect(await file.lastModified(), isNot(stamp));
    expect(await file.readAsString(), 'proxies: []\nrules: []\n');
  });

  test(
    'subscription additions are merged before validating the temp file',
    () async {
      const profile = Profile(
        id: 'additions',
        autoUpdateDuration: Duration(hours: 1),
        addedNodes: [
          {
            'name': 'local',
            'type': 'socks5',
            'server': 'localhost',
            'port': 1080,
          },
        ],
        addedProviders: {
          'extra': {'type': 'http', 'url': 'https://example.invalid/nodes'},
        },
      );
      final previous = clashCore.clashInterface;
      final core = SaveCore();
      clashCore.clashInterface = core;
      addTearDown(() => clashCore.clashInterface = previous);
      final saved = await profile.saveFile(
        utf8.encode('''
proxies: [{name: local, type: socks5, server: upstream.invalid, port: 8080}]
rules: ["MATCH,DIRECT"]
'''),
        retainAdded: true,
      );
      final config = loadYaml(core.validatedContent!) as Map;
      expect(saved.addedNodes.single['name'], 'local (2)');
      expect((config['proxies'] as List).first['name'], 'local (2)');
      expect(config['proxy-providers']['extra']['type'], 'http');
      expect(config['rules'], ['MATCH,DIRECT']);
      expect(core.validatedSetup!.scriptedConfig, isEmpty);
      expect(core.validatedSetup!.patch!.containsKey('chain-proxies'), isFalse);
      expect(core.validatedSetup!.profilePath, endsWith('.tmp'));
      expect(
        await File(await appPath.getProfilePath(profile.id)).readAsString(),
        core.validatedContent,
      );
      final restored = Profile.fromJson(jsonDecode(jsonEncode(saved)));
      expect(restored.addedNodes, saved.addedNodes);
      expect(restored.addedProviders, saved.addedProviders);
    },
  );

  test('failed patched validation leaves the old file intact', () async {
    const profile = Profile(
      id: 'failed',
      autoUpdateDuration: Duration(hours: 1),
    );
    await profile.saveFile(utf8.encode('proxies: []\n'), validate: false);
    final previous = clashCore.clashInterface;
    final core = SaveCore()..error = 'invalid test config';
    clashCore.clashInterface = core;
    addTearDown(() => clashCore.clashInterface = previous);
    await expectLater(
      profile.saveFile(utf8.encode('proxies: []\nrules: []\n')),
      throwsA('invalid test config'),
    );
    expect(
      await File(await appPath.getProfilePath(profile.id)).readAsString(),
      'proxies: []\n',
    );
    expect(await File(core.validatedSetup!.profilePath).exists(), isFalse);
  });
}
