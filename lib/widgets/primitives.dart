// SQL Pulse — shared UI primitives (ported from styles.css + components.jsx).
import 'package:flutter/material.dart';
import '../data/engines.dart';
import '../theme/tokens.dart';
import 'icons.dart';

// ---- time helpers ----
String timeAgo(int ts) {
  final s = ((DateTime.now().millisecondsSinceEpoch - ts) / 1000).floor();
  if (s < 60) return '${s}s ago';
  final mn = (s / 60).floor();
  if (mn < 60) return '${mn}m ago';
  final h = (mn / 60).floor();
  if (h < 24) return '${h}h ago';
  return '${(h / 24).floor()}d ago';
}

// ---- eyebrow label ----
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: sans(
        size: 10.5,
        weight: FontWeight.w700,
        color: color ?? c.text3,
        spacing: 1.4,
      ),
    );
  }
}

// ---- icon button ----
class IconBtn extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  final double box;
  final double iconSize;
  final Color? color;
  const IconBtn(
    this.name, {
    super.key,
    this.onTap,
    this.box = 44,
    this.iconSize = 18,
    this.color,
  });

  static const Map<String, String> _hints = {
    'x': 'Close',
    'cog': 'Settings',
    'shield': 'Security',
    'moon': 'Dark theme',
    'sun': 'Light theme',
    'more': 'Menu',
    'zap': 'Command bar',
    'search': 'Inspect',
    'trash': 'Delete',
    'plus': 'Add',
    'minus': 'Remove',
    'scan': 'Fit view',
    'arrowL': 'Back',
    'terminal': 'Run',
    'rerun': 'Re-run',
  };

  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Tooltip(
        message: _hints[name] ?? name,
        child: Container(
          width: box,
          height: box,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child: SpIcon(name, size: iconSize, color: color ?? c.text2),
        ),
      ),
    );
  }
}

// ---- badge ----
class SpBadge extends StatelessWidget {
  final String text;
  final String variant; // '', pk, fk, accent, ok, warn, err
  final String? icon;
  final Color? fg;
  final Color? bg;
  final EdgeInsets? padding;
  final double fontSize;
  const SpBadge(
    this.text, {
    super.key,
    this.variant = '',
    this.icon,
    this.fg,
    this.bg,
    this.padding,
    this.fontSize = 10,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    Color color = c.text2;
    Color bgc = c.surface3;
    Color border = c.border;
    switch (variant) {
      case 'pk':
      case 'warn':
        color = c.warning;
        bgc = c.warningSoft;
        border = Colors.transparent;
        break;
      case 'fk':
        color = c.info;
        bgc = c.info.withOpacity(0.12);
        border = Colors.transparent;
        break;
      case 'accent':
        color = c.accent;
        bgc = c.accentSoft;
        border = Colors.transparent;
        break;
      case 'ok':
        color = c.success;
        bgc = c.successSoft;
        border = Colors.transparent;
        break;
      case 'err':
        color = c.danger;
        bgc = c.dangerSoft;
        border = Colors.transparent;
        break;
    }
    if (fg != null) color = fg!;
    if (bg != null) {
      bgc = bg!;
      border = Colors.transparent;
    }
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgc,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SpIcon(icon!, size: fontSize, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: mono(
              size: fontSize,
              weight: FontWeight.w600,
              color: color,
              spacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- chip ----
class SpChip extends StatelessWidget {
  final String label;
  final bool on;
  final String? icon;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool mono;
  final Color? onColor;
  final Color? onBorder;
  final Widget? trailing;
  const SpChip(
    this.label, {
    super.key,
    this.on = false,
    this.icon,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    this.mono = true,
    this.onColor,
    this.onBorder,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final fg = on ? (onColor ?? c.accent) : c.text2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: padding,
        constraints: const BoxConstraints(minHeight: 34),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.accentSoft : c.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? (onBorder ?? c.accentLine) : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SpIcon(icon!, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: (mono ? monoStyle : sans)(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

// small helper so SpChip can pick mono vs sans cleanly (same signature as sans())
TextStyle monoStyle({
  double size = 11.5,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? spacing,
}) => mono(
  size: size,
  weight: weight,
  color: color,
  height: height,
  spacing: spacing,
);

// ---- segmented control ----
class SegItem<T> {
  final T value;
  final String label;
  final String? icon;
  const SegItem(this.value, this.label, {this.icon});
}

class Segmented<T> extends StatelessWidget {
  final List<SegItem<T>> items;
  final T value;
  final ValueChanged<T> onChange;
  final EdgeInsets btnPadding;
  final double fontSize;
  final bool iconOnly;
  const Segmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChange,
    this.btnPadding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    this.fontSize = 12.5,
    this.iconOnly = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: items.map((it) {
          final on = it.value == value;
          final child = Container(
            padding: btnPadding,
            decoration: BoxDecoration(
              color: on ? c.surface4 : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: on ? c.border2 : Colors.transparent),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (it.icon != null) ...[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SpIcon(it.icon!, size: 15, color: on ? c.text : c.text2),
                    ),
                  ),
                  if (!iconOnly) const SizedBox(width: 6),
                ],
                if (!iconOnly)
                  Flexible(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: sans(
                        size: fontSize,
                        weight: FontWeight.w600,
                        color: on ? c.text : c.text2,
                      ),
                    ),
                  ),
              ],
            ),
          );
          return Expanded(
            child: GestureDetector(
              onTap: () => onChange(it.value),
              child: child,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---- switch ----
class SpSwitch extends StatelessWidget {
  final bool on;
  final VoidCallback onToggle;
  const SpSwitch({super.key, required this.on, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: SizedBox(
        width: 56,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 42,
            height: 25,
            decoration: BoxDecoration(
              color: on ? c.accent : c.surface4,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: on ? Colors.transparent : c.border2),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: on ? c.accentInk : const Color(0xFFCFD8E2),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- button ----
enum BtnKind { normal, primary, ghost, danger }

class SpButton extends StatelessWidget {
  final String? label;
  final String? icon;
  final BtnKind kind;
  final bool sm;
  final bool block;
  final bool enabled;
  final VoidCallback? onTap;
  final Color? color;
  const SpButton({
    super.key,
    this.label,
    this.icon,
    this.kind = BtnKind.normal,
    this.sm = false,
    this.block = false,
    this.enabled = true,
    this.onTap,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    Color bg = c.surface2;
    Color fg = c.text;
    Color border = c.border2;
    FontWeight weight = FontWeight.w600;
    switch (kind) {
      case BtnKind.primary:
        bg = c.accent;
        fg = c.accentInk;
        border = Colors.transparent;
        weight = FontWeight.w700;
        break;
      case BtnKind.ghost:
        bg = Colors.transparent;
        break;
      case BtnKind.danger:
        bg = c.dangerSoft;
        fg = c.danger;
        border = Colors.transparent;
        break;
      case BtnKind.normal:
        break;
    }
    if (color != null) fg = color!;
    final content = Container(
      height: sm ? 36 : 44,
      padding: EdgeInsets.symmetric(horizontal: sm ? 12 : 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(sm ? 10 : 12),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            SpIcon(icon!, size: sm ? 14 : 16, color: fg),
            if (label != null) const SizedBox(width: 8),
          ],
          if (label != null)
            Flexible(
              child: Text(
                label!,
                overflow: TextOverflow.ellipsis,
                style: sans(size: sm ? 12.5 : 13.5, weight: weight, color: fg),
              ),
            ),
        ],
      ),
    );
    final w = Opacity(opacity: enabled ? 1 : 0.4, child: content);
    final tappable = GestureDetector(onTap: enabled ? onTap : null, child: w);
    return block ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

// ---- input ----
class SpInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  final bool mono;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final bool autofocus;
  final EdgeInsets? padding;
  final FocusNode? focusNode;
  const SpInput({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.obscure = false,
    this.mono = true,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.padding,
    this.focusNode,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final style = mono
        ? monoStyle(size: 13, color: c.text)
        : sans(size: 13, color: c.text);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      obscureText: obscure,
      autofocus: autofocus,
      minLines: minLines,
      maxLines: obscure ? 1 : maxLines,
      keyboardType: keyboardType,
      textAlign: textAlign,
      style: style.copyWith(height: 1.4),
      cursorColor: c.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: style.copyWith(color: c.text4),
        filled: true,
        fillColor: c.surface2,
        contentPadding:
            padding ?? const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: c.border2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: c.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: c.accentLine),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String label;
  final String? hint;
  const FieldLabel(this.label, {super.key, this.hint});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: sans(size: 11.5, weight: FontWeight.w600, color: c.text2),
          children: [
            TextSpan(text: label),
            if (hint != null)
              TextSpan(
                text: ' · $hint',
                style: sans(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: c.text4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- card ----
class SpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;
  const SpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.onTap,
    this.radius = R.lg,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    final w = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.border),
        boxShadow: c.dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0x121C1A16),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: child,
    );
    return onTap != null ? GestureDetector(onTap: onTap, child: w) : w;
  }
}

// ---- list row ----
class RowIco extends StatelessWidget {
  final String icon;
  final double box;
  final double iconSize;
  final Color? bg;
  final Color? fg;
  const RowIco(
    this.icon, {
    super.key,
    this.box = 36,
    this.iconSize = 18,
    this.bg,
    this.fg,
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: bg ?? c.surface3,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: SpIcon(icon, size: iconSize, color: fg ?? c.text2),
    );
  }
}

class SpRow extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const SpRow({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
  });
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(R.r),
          border: Border.all(color: selected ? c.accentLine : c.border),
          boxShadow: c.dark
              ? null
              : [
                  BoxShadow(
                    color: const Color(0x121C1A16),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: child,
      ),
    );
  }
}

// ---- empty state ----
class Empty extends StatelessWidget {
  final String icon;
  final String title;
  final String? sub;
  const Empty({super.key, required this.icon, required this.title, this.sub});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: SpIcon(icon, size: 26, color: c.text3),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: sans(size: 14, weight: FontWeight.w600, color: c.text2),
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  sub!,
                  textAlign: TextAlign.center,
                  style: sans(size: 12.5, color: c.text3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- spinner ----
class Spinner extends StatelessWidget {
  final double size;
  const Spinner({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: (size / 11).clamp(2, 6),
        valueColor: AlwaysStoppedAnimation(c.accent),
        backgroundColor: c.surface4,
      ),
    );
  }
}

// ---- tag dot ----
class TagDot extends StatelessWidget {
  final String tag;
  final double size;
  const TagDot(this.tag, {super.key, this.size = 10});
  @override
  Widget build(BuildContext context) {
    final c = SpColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kTagColors[tag] ?? c.text3,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ---- engine identity ----
class EngineTag extends StatelessWidget {
  final String engine;
  final double fontSize;
  final EdgeInsets? padding;
  const EngineTag(this.engine, {super.key, this.fontSize = 10, this.padding});
  @override
  Widget build(BuildContext context) {
    final e = eng(engine);
    final col = Color(e.color);
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            e.short,
            style: mono(size: fontSize, weight: FontWeight.w600, color: col),
          ),
        ],
      ),
    );
  }
}

class EngineMark extends StatelessWidget {
  final String engine;
  final double size;
  final double radius;
  const EngineMark(this.engine, {super.key, this.size = 42, this.radius = 12});
  @override
  Widget build(BuildContext context) {
    final e = eng(engine);
    final col = Color(e.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: col.withOpacity(0.13),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: SpIcon('database', size: size * 0.46, color: col),
    );
  }
}

class RoleGlyph extends StatelessWidget {
  final String role;
  final double size;
  final Color? color;
  const RoleGlyph(this.role, {super.key, this.size = 18, this.color});
  @override
  Widget build(BuildContext context) {
    const map = {
      'Admin': 'shield',
      'Developer': 'wrench',
      'Analyst': 'chart',
      'ReadOnly': 'eye',
    };
    return SpIcon(map[role] ?? 'eye', size: size, color: color);
  }
}
