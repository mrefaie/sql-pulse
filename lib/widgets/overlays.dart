// SQL Pulse — bottom sheets & centered dialogs (ported from .sheet / .dialog).
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'icons.dart';
import 'primitives.dart';

/// Bottom-sheet scaffold: grip + optional title bar + content.
class SpSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? right;
  final VoidCallback onClose;
  const SpSheet({super.key, this.title, required this.child, this.right, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: c.border2)),
      ),
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 22 + media.viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 38, height: 4, margin: const EdgeInsets.only(top: 6, bottom: 14), decoration: BoxDecoration(color: c.borderStrong, borderRadius: BorderRadius.circular(2)))),
        if (title != null || right != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(child: Text(title ?? '', style: sans(size: 16, weight: FontWeight.w700, color: c.text, spacing: -0.2))),
              if (right != null) Padding(padding: const EdgeInsets.only(right: 8), child: right!),
              IconBtn('x', box: 32, iconSize: 17, onTap: onClose),
            ]),
          ),
        Flexible(child: SingleChildScrollView(child: child)),
      ]),
    );
  }
}

Future<T?> showSpSheet<T>(BuildContext context, Widget Function(BuildContext) builder) {
  final c = SpColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: c.scrim,
    builder: builder,
  );
}

/// Centered dialog.
class SpDialog extends StatelessWidget {
  final String? icon;
  final Color? iconColor;
  final String? title;
  final Widget? sub;
  final Widget child;
  final double width;
  const SpDialog({super.key, this.icon, this.iconColor, this.title, this.sub, required this.child, this.width = 340});

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final ic = iconColor ?? c.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.border2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(c.dark ? 0.5 : 0.18), blurRadius: 44, offset: const Offset(0, 18))],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (icon != null || title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(children: [
                      if (icon != null)
                        Container(
                          width: 48, height: 48, margin: const EdgeInsets.only(bottom: 9),
                          decoration: BoxDecoration(color: ic.withOpacity(0.13), borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: SpIcon(icon!, size: 24, color: ic),
                        ),
                      if (title != null) Text(title!, textAlign: TextAlign.center, style: sans(size: 16.5, weight: FontWeight.w700, color: c.text, height: 1.25, spacing: -0.3)),
                      if (sub != null) Padding(padding: const EdgeInsets.only(top: 7), child: DefaultTextStyle(style: sans(size: 12.5, color: c.text2, height: 1.5), textAlign: TextAlign.center, child: sub!)),
                    ]),
                  ),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showSpDialog<T>(BuildContext context, Widget Function(BuildContext) builder) {
  final c = SpColors.of(context);
  return showDialog<T>(
    context: context,
    barrierColor: c.scrim,
    builder: builder,
  );
}
