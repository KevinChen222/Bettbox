import 'dart:io';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/plugins/app.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

class AppDisguiseView extends ConsumerStatefulWidget {
  const AppDisguiseView({super.key});

  @override
  ConsumerState<AppDisguiseView> createState() => _AppDisguiseViewState();
}

class _AppDisguiseViewState extends ConsumerState<AppDisguiseView> {
  bool _isBusy = false;

  Future<void> _editAppName() async {
    final currentName = ref.read(
      appSettingProvider.select((state) => state.customAppName),
    );
    final result = await globalState.showCommonDialog<String>(
      child: _CustomAppNameDialog(initialValue: currentName ?? ''),
    );
    if (result == null) return;
    final trimmed = result.trim();
    final nextName = trimmed.isEmpty ? null : trimmed;
    final iconPath = ref.read(
      appSettingProvider.select((state) => state.customAppIconPath),
    );
    ref
        .read(appSettingProvider.notifier)
        .updateState((state) => state.copyWith(customAppName: nextName));
    await syncNativeAppDisguise(name: nextName, iconPath: iconPath);
    if (!mounted) return;
    globalState.showNotifier(
      nextName == null ? '已恢复默认应用名称' : '应用名称已更新为「$nextName」',
    );
  }

  Future<void> _pickCustomIcon() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      String? pickedPath;
      try {
        final xFile = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        pickedPath = xFile?.path;
      } catch (_) {
        final file = await picker.pickerFile(
          allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        );
        pickedPath = file?.path;
      }
      if (pickedPath == null || pickedPath.isEmpty) return;

      final previousPath = ref.read(
        appSettingProvider.select((state) => state.customAppIconPath),
      );
      final savedPath = await saveCustomAppIconFromFile(
        pickedPath,
        previousPath: previousPath,
      );
      final customName = ref.read(
        appSettingProvider.select((state) => state.customAppName),
      );
      ref
          .read(appSettingProvider.notifier)
          .updateState((state) => state.copyWith(customAppIconPath: savedPath));
      await syncNativeAppDisguise(name: customName, iconPath: savedPath);
      if (!mounted) return;
      globalState.showNotifier('已更新展示图标');
    } catch (e) {
      commonPrint.warn('Pick custom app icon failed: $e');
      if (!mounted) return;
      globalState.showNotifier('图片解析失败，请选择有效的 PNG/JPG/WebP 图片');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _resetBranding() async {
    if (_isBusy) return;
    final previousPath = ref.read(
      appSettingProvider.select((state) => state.customAppIconPath),
    );
    ref
        .read(appSettingProvider.notifier)
        .updateState(
          (state) =>
              state.copyWith(customAppName: null, customAppIconPath: null),
        );
    await deleteCustomAppIcon(previousPath);
    await syncNativeAppDisguise(name: null, iconPath: null);
    if (!mounted) return;
    globalState.showNotifier('已恢复默认名称与图标');
  }

  Future<void> _pinCustomShortcut() async {
    if (!system.isAndroid || _isBusy) return;
    final supported = await app.isPinShortcutSupported();
    if (!supported) {
      if (!mounted) return;
      globalState.showNotifier('当前桌面不支持快捷方式添加');
      return;
    }
    final (customName, customIconPath) = ref.read(
      appSettingProvider.select(
        (state) => (state.customAppName, state.customAppIconPath),
      ),
    );
    final ok = await app.pinCustomShortcut(
      name: effectiveAppName(customName),
      iconPath: resolveCustomAppIconFile(customIconPath)?.path,
    );
    if (!mounted) return;
    globalState.showNotifier(ok ? '请在系统弹窗中确认添加' : '添加失败');
  }

  Future<void> _pinCustomWidget() async {
    if (!system.isAndroid || _isBusy) return;
    final supported = await app.isPinWidgetSupported();
    if (!supported) {
      if (!mounted) return;
      globalState.showNotifier('请从桌面小组件列表添加「桌面图标 (1×1)」');
      return;
    }
    final (customName, customIconPath) = ref.read(
      appSettingProvider.select(
        (state) => (state.customAppName, state.customAppIconPath),
      ),
    );
    final ok = await app.pinCustomWidget(
      name: effectiveAppName(customName),
      iconPath: resolveCustomAppIconFile(customIconPath)?.path,
    );
    if (!mounted) return;
    globalState.showNotifier(ok ? '请在系统弹窗中确认添加' : '添加失败');
  }

  Future<void> _selectLauncherPreset(AppDisguisePreset preset) async {
    if (!system.isAndroid || _isBusy) return;
    final currentPreset = ref.read(
      appSettingProvider.select((state) => state.androidLauncherPreset),
    );
    if (currentPreset == preset.id) return;

    final confirmed = await globalState.showMessage(
      title: '切换应用抽屉图标',
      message: TextSpan(text: '切换为「${preset.title}」？'),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      final ok = await app.setLauncherPreset(preset.id);
      if (!ok) {
        if (!mounted) return;
        globalState.showNotifier('切换失败');
        return;
      }
      ref
          .read(appSettingProvider.notifier)
          .updateState(
            (state) => state.copyWith(androidLauncherPreset: preset.id),
          );
      if (!mounted) return;
      globalState.showNotifier('已切换为「${preset.title}」');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Color _sectionSurfaceColor(ColorScheme colorScheme) {
    final isLight = colorScheme.brightness == Brightness.light;
    return isLight
        ? Color.lerp(colorScheme.surface, colorScheme.surfaceContainerLowest, 0.5)!
        : colorScheme.surfaceContainerHigh;
  }

  Widget _buildPreviewIcon({
    required BuildContext context,
    required File? customIconFile,
    required AppDisguisePreset preset,
  }) {
    final colorScheme = context.colorScheme;
    final Widget artwork;
    if (customIconFile != null) {
      artwork = Image.file(
        customIconFile,
        key: ValueKey(customIconFile.path),
        width: 78,
        height: 78,
        fit: BoxFit.cover,
      );
    } else if (preset.id == AppDisguisePreset.defaultPreset.id) {
      artwork = Image.asset(
        'assets/images/icon.png',
        width: 78,
        height: 78,
        fit: BoxFit.cover,
      );
    } else {
      artwork = Container(
        width: 78,
        height: 78,
        color: preset.backgroundColor,
        alignment: Alignment.center,
        child: Icon(preset.icon, color: Colors.white, size: 38),
      );
    }

    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: colorScheme.brightness == Brightness.light ? 0.08 : 0.28,
            ),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21.2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            if (_isBusy)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroIdentityStage({
    required BuildContext context,
    required String displayName,
    required File? customIconFile,
    required AppDisguisePreset preset,
    required bool hasCustomBranding,
  }) {
    final colorScheme = context.colorScheme;
    final badgeRingColor = _sectionSurfaceColor(colorScheme);

    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
            child: Column(
              children: [
                GestureDetector(
                  key: const ValueKey('disguise-icon-button'),
                  onTap: _isBusy ? null : _pickCustomIcon,
                  behavior: HitTestBehavior.opaque,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildPreviewIcon(
                        context: context,
                        customIconFile: customIconFile,
                        preset: preset,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: badgeRingColor,
                              width: 2.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 15,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  key: const ValueKey('disguise-name-button'),
                  onTap: _isBusy ? null : _editAppName,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasCustomBranding)
          Positioned(
            top: 10,
            right: 10,
            child: TextButton(
              key: const ValueKey('disguise-reset-button'),
              onPressed: _isBusy ? null : _resetBranding,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: context.textTheme.labelMedium,
              ),
              child: const Text('恢复默认'),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopActions(BuildContext context) {
    final colorScheme = context.colorScheme;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: colorScheme.secondaryContainer,
      foregroundColor: colorScheme.onSecondaryContainer,
      elevation: 0,
      shadowColor: Colors.transparent,
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: context.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              '添加到桌面',
              style: context.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _isBusy ? null : _pinCustomWidget,
                  style: buttonStyle,
                  icon: const Icon(Icons.widgets_outlined, size: 17),
                  label: const Text(
                    '小组件 1×1',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _isBusy ? null : _pinCustomShortcut,
                  style: buttonStyle,
                  icon: const Icon(Icons.shortcut_rounded, size: 17),
                  label: const Text(
                    '快捷方式',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetLeading(AppDisguisePreset option) {
    if (option.id == AppDisguisePreset.defaultPreset.id) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/images/icon.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: option.backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(option.icon, color: Colors.white, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (customName, customIconPath, presetId) = ref.watch(
      appSettingProvider.select(
        (state) => (
          state.customAppName,
          state.customAppIconPath,
          state.androidLauncherPreset,
        ),
      ),
    );
    final displayName = effectiveAppName(customName);
    final customIconFile = resolveCustomAppIconFile(customIconPath);
    final preset = AppDisguisePreset.fromId(presetId);
    final hasCustomBranding =
        (customName != null && customName.trim().isNotEmpty) ||
        customIconFile != null;

    final items = <Widget>[
      ...generateSection(
        isFirst: true,
        items: [
          _buildHeroIdentityStage(
            context: context,
            displayName: displayName,
            customIconFile: customIconFile,
            preset: preset,
            hasCustomBranding: hasCustomBranding,
          ),
          if (system.isAndroid) _buildDesktopActions(context),
        ],
      ),
      if (system.isAndroid)
        ...generateSection(
          title: '应用抽屉图标',
          items: [
            for (final option in AppDisguisePreset.values)
              ListItem(
                leading: _buildPresetLeading(option),
                title: Text(option.title),
                trailing: Icon(
                  presetId == option.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: presetId == option.id
                      ? context.colorScheme.primary
                      : context.colorScheme.onSurfaceVariant,
                ),
                onTap: _isBusy ? null : () => _selectLauncherPreset(option),
              ),
          ],
        ),
    ];

    return generateListView(items);
  }
}

class _CustomAppNameDialog extends StatefulWidget {
  final String initialValue;

  const _CustomAppNameDialog({required this.initialValue});

  @override
  State<_CustomAppNameDialog> createState() => _CustomAppNameDialogState();
}

class _CustomAppNameDialogState extends State<_CustomAppNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: '自定义应用名称',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('恢复默认'),
        ),
        TextButton(onPressed: _submit, child: Text(appLocalizations.confirm)),
      ],
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: _controller,
          maxLength: 24,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: '例如：笔记、系统工具',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
