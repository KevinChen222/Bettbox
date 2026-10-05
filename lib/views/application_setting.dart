import 'package:bett_box/common/common.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:bett_box/views/dashboard/dashboard.dart'
    show customDashboardTitleProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CloseConnectionsItem extends ConsumerWidget {
  const CloseConnectionsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final closeConnections = ref.watch(
      appSettingProvider.select((state) => state.closeConnections),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoCloseConnections),
      subtitle: Text(appLocalizations.autoCloseConnectionsDesc),
      delegate: SwitchDelegate(
        value: closeConnections,
        onChanged: (value) async {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(closeConnections: value));
        },
      ),
    );
  }
}

class UsageItem extends ConsumerWidget {
  const UsageItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final onlyStatisticsProxy = ref.watch(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.onlyStatisticsProxy),
      subtitle: Text(appLocalizations.onlyStatisticsProxyDesc),
      delegate: SwitchDelegate(
        value: onlyStatisticsProxy,
        onChanged: (bool value) async {
          ref
              .read(appSettingProvider.notifier)
              .updateState(
                (state) => state.copyWith(onlyStatisticsProxy: value),
              );
        },
      ),
    );
  }
}

class AutoLaunchItem extends ConsumerWidget {
  const AutoLaunchItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoLaunch = ref.watch(
      appSettingProvider.select((state) => state.autoLaunch),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoLaunch),
      subtitle: Text(appLocalizations.autoLaunchDesc),
      delegate: SwitchDelegate(
        value: autoLaunch,
        onChanged: (bool value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(autoLaunch: value));
        },
      ),
    );
  }
}

class SilentLaunchItem extends ConsumerWidget {
  const SilentLaunchItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final silentLaunch = ref.watch(
      appSettingProvider.select((state) => state.silentLaunch),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.silentLaunch),
      subtitle: Text(appLocalizations.silentLaunchDesc),
      delegate: SwitchDelegate(
        value: silentLaunch,
        onChanged: (bool value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(silentLaunch: value));
        },
      ),
    );
  }
}

class AutoRunItem extends ConsumerWidget {
  const AutoRunItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRun = ref.watch(
      appSettingProvider.select((state) => state.autoRun),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoRun),
      subtitle: Text(appLocalizations.autoRunDesc),
      delegate: SwitchDelegate(
        value: autoRun,
        onChanged: (bool value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(autoRun: value));
        },
      ),
    );
  }
}

class HiddenItem extends ConsumerWidget {
  const HiddenItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      appSettingProvider.select((state) => state.hidden),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.exclude),
      subtitle: Text(appLocalizations.excludeDesc),
      delegate: SwitchDelegate(
        value: hidden,
        onChanged: (value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(hidden: value));
        },
      ),
    );
  }
}

class KeepDockIconItem extends ConsumerWidget {
  const KeepDockIconItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepDockIcon = ref.watch(
      appSettingProvider.select((state) => state.keepDockIcon),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.keepDockIcon),
      subtitle: Text(appLocalizations.keepDockIconDesc),
      delegate: SwitchDelegate(
        value: keepDockIcon,
        onChanged: (value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(keepDockIcon: value));
        },
      ),
    );
  }
}

class ShowStartSwitchItem extends ConsumerWidget {
  const ShowStartSwitchItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showStartSwitch = ref.watch(
      appSettingProvider.select((state) => state.showStartSwitch),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.showStartSwitch),
      subtitle: Text(appLocalizations.showStartSwitchDesc),
      delegate: SwitchDelegate(
        value: showStartSwitch,
        onChanged: (value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(showStartSwitch: value));
        },
      ),
    );
  }
}

class AlwaysShowTitleBarItem extends ConsumerWidget {
  const AlwaysShowTitleBarItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alwaysShowTitleBar = ref.watch(
      vpnSettingProvider.select((state) => state.alwaysShowTitleBar),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.alwaysShowTitleBar),
      subtitle: Text(appLocalizations.alwaysShowTitleBarDesc),
      delegate: SwitchDelegate(
        value: alwaysShowTitleBar,
        onChanged: (bool value) async {
          ref
              .read(vpnSettingProvider.notifier)
              .updateState(
                (state) => state.copyWith(alwaysShowTitleBar: value),
              );
        },
      ),
    );
  }
}

class NavBarHapticFeedbackItem extends ConsumerWidget {
  const NavBarHapticFeedbackItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enableNavBarHapticFeedback = ref.watch(
      appSettingProvider.select((state) => state.enableNavBarHapticFeedback),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.navBarHapticFeedback),
      subtitle: Text(appLocalizations.navBarHapticFeedbackDesc),
      delegate: SwitchDelegate(
        value: enableNavBarHapticFeedback,
        onChanged: (value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState(
                (state) => state.copyWith(enableNavBarHapticFeedback: value),
              );
        },
      ),
    );
  }
}

class AutoCheckUpdateItem extends ConsumerWidget {
  const AutoCheckUpdateItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoCheckUpdate = ref.watch(
      appSettingProvider.select((state) => state.autoCheckUpdate),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoCheckUpdate),
      subtitle: Text(appLocalizations.autoCheckUpdateDesc),
      delegate: SwitchDelegate(
        value: autoCheckUpdate,
        onChanged: (bool value) {
          ref
              .read(appSettingProvider.notifier)
              .updateState((state) => state.copyWith(autoCheckUpdate: value));
        },
      ),
    );
  }
}

class ApplicationSettingView extends StatelessWidget {
  const ApplicationSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [
      AutoLaunchItem(),
      if (system.isDesktop) ...[SilentLaunchItem()],
      AutoRunItem(),
      if (system.isAndroid) ...[HiddenItem()],
      if (system.isDesktop) ...[
        if (system.isWindows || system.isLinux) const AlwaysShowTitleBarItem(),
      ],
      const ShowStartSwitchItem(),
      const MainPageTitlesItem(),
      if (system.isAndroid) ...[NavBarHapticFeedbackItem()],
      if (system.isMacOS) const KeepDockIconItem(),
      CloseConnectionsItem(),
      UsageItem(),
      AutoCheckUpdateItem(),
    ];
    return generateListView(generateSection(items: items));
  }
}

String _titleText(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'zh' ? chinese : english;

class MainPageTitlesItem extends ConsumerWidget {
  const MainPageTitlesItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListItem(
    title: Text(_titleText(context, '主页面左上角标题', 'Main page titles')),
    subtitle: Text(
      _titleText(
        context,
        '分别自定义首页、代理、配置和更多的标题',
        'Customize Home, Proxies, Profiles and More titles',
      ),
    ),
    onTap: () async {
      final titles = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _PageTitlesDialog(
          titles: ref.read(appSettingProvider).pageTitles,
          legacyDashboardTitle: ref.read(customDashboardTitleProvider),
        ),
      );
      if (titles == null || !context.mounted) return;
      ref
          .read(appSettingProvider.notifier)
          .updateState((state) => state.copyWith(pageTitles: titles));
      await ref.read(customDashboardTitleProvider.notifier).updateTitle(null);
    },
  );
}

class _PageTitlesDialog extends StatefulWidget {
  const _PageTitlesDialog({required this.titles, this.legacyDashboardTitle});
  final Map<String, String> titles;
  final String? legacyDashboardTitle;

  @override
  State<_PageTitlesDialog> createState() => _PageTitlesDialogState();
}

class _PageTitlesDialogState extends State<_PageTitlesDialog> {
  late final _defaults = {
    'dashboard': appLocalizations.dashboard,
    'proxies': appLocalizations.proxies,
    'profiles': appLocalizations.profiles,
    'tools': appLocalizations.tools,
  };
  late final _controllers = {
    for (final entry in _defaults.entries)
      entry.key: TextEditingController(
        text:
            widget.titles[entry.key] ??
            (entry.key == 'dashboard' ? widget.legacyDashboardTitle : null) ??
            entry.value,
      ),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_titleText(context, '主页面左上角标题', 'Main page titles')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _titleText(
              context,
              '留空可隐藏标题。底部 Dock 栏名称保持不变。',
              'Leave blank to hide a title. Dock labels stay the same.',
            ),
          ),
          for (final entry in _controllers.entries)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextField(
                controller: entry.value,
                decoration: InputDecoration(labelText: _defaults[entry.key]),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, <String, String>{}),
        child: Text(_titleText(context, '恢复默认', 'Reset')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(appLocalizations.cancel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, {
          for (final entry in _controllers.entries)
            if (entry.value.text.trim() != _defaults[entry.key])
              entry.key: entry.value.text.trim(),
        }),
        child: Text(appLocalizations.save),
      ),
    ],
  );
}
