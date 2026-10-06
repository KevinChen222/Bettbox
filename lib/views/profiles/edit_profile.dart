import 'dart:convert';
import 'dart:io';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/features/node_import/menu.dart';
import 'package:bett_box/features/node_import/nodes.dart';
import 'package:bett_box/features/node_import/view.dart';
import 'package:bett_box/features/node_import/delete.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/pages/editor.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

class EditProfileView extends StatefulWidget {
  final Profile profile;
  final BuildContext context;
  final bool isNew;

  const EditProfileView({
    super.key,
    required this.context,
    required this.profile,
    this.isNew = false,
  });

  @override
  State<EditProfileView> createState() => EditProfileViewState();
}

class EditProfileViewState extends State<EditProfileView> {
  late TextEditingController labelController;
  late TextEditingController urlController;
  late TextEditingController autoUpdateDurationController;
  late bool autoUpdate;
  late TextEditingController ageSecretKeyController;
  FocusNode? urlFocusNode;
  bool _obscureAgeSecretKey = true;
  String? rawText;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final fileInfoNotifier = ValueNotifier<FileInfo?>(null);
  Uint8List? fileData;
  bool _hasUnretainedEdits = false;
  late final _addedNodes = [
    for (final node in profile.addedNodes) Map<String, dynamic>.from(node),
  ];
  late final _addedProviders = Map<String, Map<String, dynamic>>.from(
    profile.addedProviders,
  );

  Profile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    labelController = TextEditingController(text: widget.profile.label);
    urlController = TextEditingController(text: widget.profile.url);
    autoUpdate = widget.isNew ? false : widget.profile.autoUpdate;
    autoUpdateDurationController = TextEditingController(
      text: widget.profile.autoUpdateDuration.inMinutes.toString(),
    );
    ageSecretKeyController = TextEditingController(
      text: widget.profile.ageSecretKey,
    );
    if (widget.isNew) {
      urlFocusNode = FocusNode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            urlFocusNode?.requestFocus();
          }
        });
      });
    }
    appPath.getProfilePath(widget.profile.id).then((path) async {
      fileInfoNotifier.value = await _getFileInfo(path);
    });
  }

  @override
  void dispose() {
    labelController.dispose();
    urlController.dispose();
    autoUpdateDurationController.dispose();
    ageSecretKeyController.dispose();
    urlFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    final appController = globalState.appController;
    Profile profile = this.profile.copyWith(
      url: urlController.text,
      label: labelController.text.trim().isEmpty
          ? null
          : labelController.text.trim(),
      ageSecretKey: ageSecretKeyController.text.trim().isEmpty
          ? null
          : ageSecretKeyController.text.trim(),
      autoUpdate: autoUpdate,
      autoUpdateDuration: Duration(
        minutes: int.parse(autoUpdateDurationController.text),
      ),
      addedNodes: List.from(_addedNodes),
      addedProviders: Map.from(_addedProviders),
    );
    if (widget.isNew) {
      final ref = appController.ref;
      ref.read(loadingProvider.notifier).value = true;
      try {
        final updatedProfile = await profile.update();
        await appController.addProfile(updatedProfile);
      } on Object catch (e) {
        if (mounted) {
          await globalState.showMessage(
            title: appLocalizations.tip,
            message: TextSpan(text: e.formatError),
            cancelable: false,
          );
        }
        return;
      } finally {
        ref.read(loadingProvider.notifier).value = false;
      }
    } else {
      final hasUpdate = widget.profile.url != profile.url;
      if (fileData != null) {
        if (profile.type == ProfileType.url &&
            autoUpdate &&
            _hasUnretainedEdits) {
          final res = await globalState.showMessage(
            title: appLocalizations.tip,
            message: TextSpan(text: appLocalizations.profileHasUpdate),
          );
          if (res == true) {
            profile = profile.copyWith(autoUpdate: false);
          }
        }
        try {
          if (_addedNodes.isNotEmpty || _addedProviders.isNotEmpty) {
            final config = loadYaml(utf8.decode(fileData!)) as Map;
            profile = profile.copyWith(
              addedNodes: [
                for (final node in config['proxies'] as List? ?? [])
                  if (_addedNodes.any((added) => added['name'] == node['name']))
                    Map<String, dynamic>.from(node as Map),
              ],
              addedProviders: {
                for (final entry
                    in (config['proxy-providers'] as Map? ?? {}).entries)
                  if (_addedProviders.containsKey(entry.key))
                    entry.key as String: Map<String, dynamic>.from(
                      entry.value as Map,
                    ),
              },
            );
          }
          final updatedProfile = await profile.saveFile(fileData!);
          appController.setProfileAndAutoApply(updatedProfile);
        } catch (e) {
          if (mounted) {
            await globalState.showMessage(
              title: appLocalizations.tip,
              message: TextSpan(text: e.toString()),
              cancelable: false,
            );
          }
          return;
        }
      } else if (!hasUpdate) {
        appController.setProfileAndAutoApply(profile);
      } else {
        try {
          await Future.delayed(commonDuration);
          await appController.updateProfile(profile);
        } on Object catch (e) {
          await globalState.showMessage(
            title: appLocalizations.tip,
            message: TextSpan(
              text: '${profile.label ?? profile.id}: ${e.formatError}',
            ),
            cancelable: false,
          );
        }
      }
    }
    if (mounted) {
      Navigator.of(context).pop();
      if (widget.isNew && widget.context.mounted) {
        Navigator.of(widget.context).pop();
      }
    }
  }

  void _setAutoUpdate(bool value) {
    if (autoUpdate == value) return;
    setState(() {
      autoUpdate = value;
    });
  }

  Future<FileInfo?> _getFileInfo(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final lastModified = await file.lastModified();
    final size = await file.length();
    return FileInfo(size: size, lastModified: lastModified);
  }

  Future<void> _handleSaveEdit(BuildContext context, String data) async {
    final message = await globalState.appController.safeRun<String>(() async {
      final originalMessage = await clashCore.validateConfig(
        data,
        ageSecretKey: ageSecretKeyController.text.trim(),
      );
      if (originalMessage.isEmpty) return '';
      final patched = utils.patchValidateConfig(data);
      if (patched == data) return originalMessage;
      final patchedMessage = await clashCore.validateConfig(
        patched,
        ageSecretKey: ageSecretKeyController.text.trim(),
      );
      return patchedMessage.isEmpty ? '' : originalMessage;
    }, silence: false);
    if (message?.isNotEmpty == true) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(text: message),
        cancelable: false,
      );
      return;
    }
    if (context.mounted) {
      Navigator.of(context).pop(utils.patchValidateConfig(data));
    }
  }

  Future<void> _editProfileFile() async {
    if (rawText == null) {
      final profilePath = await appPath.getProfilePath(widget.profile.id);
      final file = File(profilePath);
      if (await file.exists()) {
        rawText = await file.readAsString();
      }
    }
    if (!mounted) return;
    final title = widget.profile.label ?? widget.profile.id;
    final editorPage = EditorPage(
      title: title,
      content: rawText!,
      onSave: (context, _, content) {
        _handleSaveEdit(context, content);
      },
      onPop: (context, _, content) async {
        if (content == rawText) {
          return true;
        }
        final res = await globalState.showMessage(
          title: title,
          message: TextSpan(text: appLocalizations.hasCacheChange),
        );
        if (res == true && context.mounted) {
          _handleSaveEdit(context, content);
        } else {
          return true;
        }
        return false;
      },
    );
    final data = await BaseNavigator.push<String>(context, editorPage);
    if (data == null) {
      return;
    }
    if (data != rawText) _hasUnretainedEdits = true;
    rawText = data;
    fileData = Uint8List.fromList(utf8.encode(data));
    fileInfoNotifier.value = fileInfoNotifier.value?.copyWith(
      size: fileData?.length ?? 0,
      lastModified: DateTime.now(),
    );
  }

  Future<void> _uploadProfileFile() async {
    final platformFile = await globalState.appController.safeRun(
      picker.pickerFile,
    );
    if (platformFile?.bytes == null) return;
    _hasUnretainedEdits = true;
    fileData = platformFile?.bytes;
    fileInfoNotifier.value = fileInfoNotifier.value?.copyWith(
      size: fileData?.length ?? 0,
      lastModified: DateTime.now(),
    );
  }

  Future<void> _addNodes(BuildContext buttonContext) async {
    try {
      var content = fileData == null ? rawText : utf8.decode(fileData!);
      if (content == null) {
        final path = await appPath.getProfilePath(profile.id);
        content = await File(path).readAsString();
      }
      final config = loadYaml(content);
      if (config is! Map) throw const FormatException('Invalid YAML profile');
      if (!buttonContext.mounted) return;
      final method = await showNodeImportMenu(buttonContext);
      if (method == null || !buttonContext.mounted) return;
      String updated;
      String notice;
      List<Map<String, dynamic>> nodesToRetain = [];
      Map<String, Map<String, dynamic>> providersToRetain = {};
      if (method == NodeImportMethod.subscription) {
        final subscription = await showSubscriptionImport(
          buttonContext,
          provider: true,
        );
        if (subscription == null || !mounted) return;
        final providers = config['proxy-providers'] as Map? ?? {};
        final name = allocateSubscriptionName(subscription.name, {
          ...nodeNames(config),
          ...providers.keys.cast<String>(),
        });
        final provider = subscriptionProvider(
          name,
          subscription.url,
          providers,
        );
        updated = addProviderToProfile(content, name, provider);
        providersToRetain = {name: provider};
        notice = nodeImportText(
          context,
          '已添加订阅 $name，保存后生效',
          'Subscription $name added. Save to apply.',
        );
      } else {
        final imported = await importExternalNodes(
          buttonContext,
          method: method,
          reservedNames: nodeNames(config),
        );
        if (imported == null || !mounted) return;
        updated = prependNodesToProfile(content, imported.nodes);
        nodesToRetain = imported.nodes;
        notice = nodeImportText(
          context,
          '已添加 ${imported.nodes.length} 个节点，保存后生效',
          '${imported.nodes.length} nodes added. Save to apply.',
        );
      }
      final message = await clashCore.validateConfig(
        utils.patchValidateConfig(updated),
        ageSecretKey: ageSecretKeyController.text.trim(),
      );
      if (message.isNotEmpty) throw FormatException(message);
      if (!mounted) return;
      setState(() {
        _addedNodes.insertAll(0, nodesToRetain);
        _addedProviders.addAll(providersToRetain);
        rawText = updated;
        fileData = Uint8List.fromList(utf8.encode(updated));
        fileInfoNotifier.value = fileInfoNotifier.value?.copyWith(
          size: fileData!.length,
          lastModified: DateTime.now(),
        );
      });
      context.showSnackBar(notice);
    } catch (error) {
      if (mounted) context.showSnackBar(error.toString());
    }
  }

  Future<void> _handleBack() async {
    final res = await globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.fileIsUpdate),
    );
    if (res == true) {
      _handleConfirm();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteNodes() async {
    try {
      var content = fileData == null ? rawText : utf8.decode(fileData!);
      content ??= await File(
        await appPath.getProfilePath(profile.id),
      ).readAsString();
      final config = loadYaml(content) as Map;
      if (!mounted) return;
      final selected = await selectNodesToDelete(
        context,
        [
          for (final node in config['proxies'] as List? ?? [])
            Map<String, dynamic>.from(node as Map),
        ],
        subscriptions: {
          for (final name in (config['proxy-providers'] as Map? ?? {}).keys)
            name as String: const [],
        },
        referenceMessage: nodeImportText(
          context,
          '同时移除策略组的订阅/节点引用及相关前置引用；没有其他成员的策略组保留 DIRECT。保存后生效。',
          'Provider, group member and dialer references will also be removed. Empty groups retain DIRECT. Save to apply.',
        ),
      );
      if (selected == null || !mounted) return;
      var updated = content;
      if (selected.subscriptions.isNotEmpty) {
        updated = removeProvidersFromProfile(updated, selected.subscriptions);
      }
      if (selected.nodes.isNotEmpty) {
        updated = removeNodesFromProfile(updated, selected.nodes);
      }
      final message = await clashCore.validateConfig(
        utils.patchValidateConfig(updated),
        ageSecretKey: ageSecretKeyController.text.trim(),
      );
      if (message.isNotEmpty) throw FormatException(message);
      if (!mounted) return;
      setState(() {
        if (selected.nodes.any(
              (name) => !_addedNodes.any((node) => node['name'] == name),
            ) ||
            selected.subscriptions.any(
              (name) => !_addedProviders.containsKey(name),
            )) {
          _hasUnretainedEdits = true;
        }
        _addedNodes.removeWhere(
          (node) => selected.nodes.contains(node['name']),
        );
        for (final node in _addedNodes) {
          if (selected.nodes.contains(node['dialer-proxy'])) {
            node.remove('dialer-proxy');
          }
        }
        _addedProviders.removeWhere(
          (name, _) => selected.subscriptions.contains(name),
        );
        rawText = updated;
        fileData = Uint8List.fromList(utf8.encode(updated));
        fileInfoNotifier.value = fileInfoNotifier.value?.copyWith(
          size: fileData!.length,
          lastModified: DateTime.now(),
        );
      });
      context.showSnackBar(
        nodeImportText(
          context,
          '已删除 ${selected.subscriptions.length} 个订阅、${selected.nodes.length} 个节点，保存后生效',
          '${selected.subscriptions.length} subscriptions and ${selected.nodes.length} nodes deleted. Save to apply.',
        ),
      );
    } catch (error) {
      if (mounted) context.showSnackBar(error.toString());
    }
  }

  void showAgeKeyGenerator() {
    globalState.showCommonDialog(child: const _AgeKeyGeneratorDialog());
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ListItem(
        title: TextFormField(
          textInputAction: TextInputAction.next,
          controller: labelController,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: appLocalizations.name,
          ),
          validator: (String? value) {
            if (!widget.isNew && (value == null || value.isEmpty)) {
              return appLocalizations.profileNameNullValidationDesc;
            }
            return null;
          },
        ),
      ),
      if (widget.profile.type == ProfileType.url || widget.isNew) ...[
        ListItem(
          title: TextFormField(
            focusNode: urlFocusNode,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.url,
            controller: urlController,
            maxLines: 5,
            minLines: 1,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: appLocalizations.url,
            ),
            onEditingComplete: widget.isNew
                ? () => FocusManager.instance.primaryFocus?.unfocus()
                : null,
            validator: (String? value) {
              if (value == null || value.isEmpty) {
                return appLocalizations.profileUrlNullValidationDesc;
              }
              if (!value.isUrl) {
                return appLocalizations.profileUrlInvalidValidationDesc;
              }
              return null;
            },
          ),
        ),
        ListItem(
          title: TextFormField(
            textInputAction: TextInputAction.next,
            controller: ageSecretKeyController,
            obscureText: _obscureAgeSecretKey,
            maxLines: 1,
            minLines: 1,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: appLocalizations.ageSecretKeyOptional,
              hintText: 'AGE-SECRET-KEY-...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureAgeSecretKey
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureAgeSecretKey = !_obscureAgeSecretKey;
                  });
                },
              ),
            ),
            validator: (String? value) {
              if (value != null && value.isNotEmpty) {
                if (!value.startsWith('AGE-SECRET-KEY-')) {
                  return appLocalizations.ageSecretKeyInvalidValidationDesc;
                }
              }
              return null;
            },
          ),
        ),
        ListItem.switchItem(
          title: Text(appLocalizations.autoUpdate),
          delegate: SwitchDelegate<bool>(
            value: autoUpdate,
            onChanged: _setAutoUpdate,
          ),
        ),
        if (autoUpdate)
          ListItem(
            title: TextFormField(
              textInputAction: TextInputAction.next,
              controller: autoUpdateDurationController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.autoUpdateInterval,
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return appLocalizations
                      .profileAutoUpdateIntervalNullValidationDesc;
                }
                try {
                  int.parse(value);
                } catch (_) {
                  return appLocalizations
                      .profileAutoUpdateIntervalInvalidValidationDesc;
                }
                return null;
              },
            ),
          ),
      ],
      if (!widget.isNew)
        ValueListenableBuilder<FileInfo?>(
          valueListenable: fileInfoNotifier,
          builder: (_, fileInfo, _) {
            return FadeThroughBox(
              child: fileInfo == null
                  ? Container()
                  : ListItem(
                      title: Text(appLocalizations.profile),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(fileInfo.desc),
                          const SizedBox(height: 8),
                          Wrap(
                            runSpacing: 6,
                            spacing: 12,
                            children: [
                              CommonChip(
                                avatar: const Icon(Icons.edit),
                                label: appLocalizations.edit,
                                onPressed: _editProfileFile,
                              ),
                              CommonChip(
                                avatar: const Icon(Icons.upload),
                                label: appLocalizations.upload,
                                onPressed: _uploadProfileFile,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            );
          },
        ),
    ];
    return CommonPopScope(
      onPop: () {
        if (dismissTvInputFocus()) {
          return false;
        }
        if (fileData == null) {
          return true;
        }
        _handleBack();
        return false;
      },
      child: Stack(
        children: [
          FloatLayout(
            floatingWidget: FloatWrapper(
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: _handleConfirm,
                label: Text(appLocalizations.save),
                icon: const Icon(Icons.save),
              ),
            ),
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: ListView.separated(
                  padding: kMaterialListPadding.copyWith(
                    bottom: 144 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  itemBuilder: (_, index) {
                    return items[index];
                  },
                  separatorBuilder: (_, _) {
                    return const SizedBox(height: 24);
                  },
                  itemCount: items.length,
                ),
              ),
            ),
          ),
          if (!widget.isNew)
            Positioned(
              left: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                right: false,
                child: FloatWrapper(
                  child: Builder(
                    builder: (buttonContext) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FloatingActionButton.extended(
                          heroTag: null,
                          onPressed: _deleteNodes,
                          label: Text(
                            nodeImportText(context, '删除节点', 'Delete nodes'),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.extended(
                          heroTag: null,
                          onPressed: () => _addNodes(buttonContext),
                          label: Text(
                            nodeImportText(context, '添加节点', 'Add nodes'),
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgeKeyGeneratorDialog extends StatefulWidget {
  const _AgeKeyGeneratorDialog();

  @override
  State<_AgeKeyGeneratorDialog> createState() => _AgeKeyGeneratorDialogState();
}

class _AgeKeyGeneratorDialogState extends State<_AgeKeyGeneratorDialog> {
  late TextEditingController _privateKeyController;
  late TextEditingController _publicKeyController;
  bool _generateFromPrivateKey = false;
  String? _helperText;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _privateKeyController = TextEditingController();
    _publicKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _privateKeyController.dispose();
    _publicKeyController.dispose();
    super.dispose();
  }

  Future<void> _handleGenerate() async {
    setState(() {
      _helperText = null;
    });

    final privateKey = _privateKeyController.text.trim();

    if (_generateFromPrivateKey) {
      if (privateKey.isEmpty || !privateKey.startsWith('AGE-SECRET-KEY-')) {
        setState(() {
          _helperText = appLocalizations.agePrivateKeyRequired;
        });
        return;
      }

      setState(() {
        _isGenerating = true;
      });

      try {
        final result = await clashCore.convertAgeSecretKeyToPublicKey(
          privateKey,
        );
        if (result.isSuccess &&
            result.data != null &&
            result.data!.isNotEmpty) {
          setState(() {
            _publicKeyController.text = result.data!;
            _helperText = null;
          });
        } else {
          setState(() {
            _helperText = appLocalizations.agePrivateKeyRequired;
          });
        }
      } catch (e) {
        setState(() {
          _helperText = appLocalizations.agePrivateKeyRequired;
        });
      } finally {
        setState(() {
          _isGenerating = false;
        });
      }
    } else {
      setState(() {
        _isGenerating = true;
      });

      try {
        final keyPair = await clashCore.generateAgeKeyPair();
        final secKey = keyPair['secret-key'] ?? '';
        final pubKey = keyPair['public-key'] ?? '';

        if (secKey.isNotEmpty && pubKey.isNotEmpty) {
          setState(() {
            _privateKeyController.text = secKey;
            _publicKeyController.text = pubKey;
            _helperText = appLocalizations.ageKeyPairGeneratedSuccess;
          });
        }
      } catch (e) {
        setState(() {
          _helperText = e.toString();
        });
      } finally {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      context.showNotifier(appLocalizations.copySuccess);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: appLocalizations.ageKeyGenerateTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: _isGenerating ? null : _handleGenerate,
          child: Text(appLocalizations.generateSecret),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _privateKeyController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelText: appLocalizations.agePrivateKeyLabel,
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyToClipboard(_privateKeyController.text),
              ),
            ),
            onChanged: (_) {
              if (_helperText != null) {
                setState(() {
                  _helperText = null;
                });
              }
            },
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _publicKeyController,
            readOnly: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelText: appLocalizations.agePublicKeyLabel,
              helperText: _helperText,
              helperMaxLines: 2,
              helperStyle: _helperText == appLocalizations.agePrivateKeyRequired
                  ? TextStyle(color: context.colorScheme.error)
                  : (_helperText == appLocalizations.ageKeyPairGeneratedSuccess
                        ? TextStyle(color: context.colorScheme.primary)
                        : null),
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyToClipboard(_publicKeyController.text),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(appLocalizations.generateFromPrivateKey),
              Switch(
                value: _generateFromPrivateKey,
                onChanged: (value) {
                  setState(() {
                    _generateFromPrivateKey = value;
                    _helperText = null;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
