import 'dart:math' as math;

import 'package:flutter/material.dart';

enum NodeImportMethod { manual, subscription }

String nodeImportText(BuildContext context, String chinese, String english) =>
    Localizations.localeOf(context).languageCode == 'zh' ? chinese : english;

Future<NodeImportMethod?> showNodeImportMenu(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
  final origin =
      box?.localToGlobal(Offset.zero, ancestor: overlay) ?? Offset.zero;
  final anchor = origin & (box?.size ?? const Size(160, 56));
  return showGeneralDialog<NodeImportMethod>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, child) {
      final media = MediaQuery.of(context);
      final width = math.min(220.0, media.size.width - 32);
      final left = anchor.left.clamp(
        16.0,
        math.max(16.0, media.size.width - width - 16),
      );
      final top = (anchor.top - 128).clamp(
        media.padding.top + 16,
        math.max(
          media.padding.top + 16,
          media.size.height - media.padding.bottom - 144,
        ),
      );
      final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return Stack(
        children: [
          Positioned(
            left: left.toDouble(),
            top: top.toDouble(),
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final method in NodeImportMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(
                            method == NodeImportMethod.manual ? 0.12 : 0.04,
                            method == NodeImportMethod.manual ? 0.65 : 0.35,
                          ),
                          end: Offset.zero,
                        ).animate(curved),
                        child: ScaleTransition(
                          alignment: Alignment.bottomLeft,
                          scale: Tween(begin: 0.85, end: 1.0).animate(curved),
                          child: FloatingActionButton.extended(
                            heroTag: null,
                            onPressed: () => Navigator.pop(context, method),
                            icon: Icon(
                              method == NodeImportMethod.manual
                                  ? Icons.edit_note
                                  : Icons.link,
                            ),
                            label: Text(
                              method == NodeImportMethod.manual
                                  ? nodeImportText(
                                      context,
                                      '手动添加',
                                      'Add manually',
                                    )
                                  : nodeImportText(
                                      context,
                                      '订阅链接',
                                      'Subscription URL',
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
