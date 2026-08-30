// SQL Pulse — design tokens (warm-dark default + warm light). Ported from styles.css.
import 'package:flutter/material.dart';

const String _sans = 'HankenGrotesk';
const String _mono = 'JetBrainsMono';

/// Radii.
class R {
  static const double xs = 7, sm = 10, r = 13, lg = 18, xl = 24;
}

/// Active theme color tokens. [accent] may be re-tinted per connection.
class SpColors {
  final bool dark;
  final Color bg, surface, surface2, surface3, surface4;
  final Color border, border2, borderStrong;
  final Color text, text2, text3, text4;
  final Color accent, accent2, accentInk;
  final Color success, warning, danger, info;
  final Color lime, limeInk, cyan;
  final Color synKw, synStr, synNum, synFn, synPunc, synComment;
  final Color navBg, dot, scrim;

  const SpColors({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.surface4,
    required this.border,
    required this.border2,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.accent,
    required this.accent2,
    required this.accentInk,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.lime,
    required this.limeInk,
    required this.cyan,
    required this.synKw,
    required this.synStr,
    required this.synNum,
    required this.synFn,
    required this.synPunc,
    required this.synComment,
    required this.navBg,
    required this.dot,
    required this.scrim,
  });

  // computed soft/line variants (recomputed when accent is tinted)
  Color get accentSoft => accent.withOpacity(dark ? 0.16 : 0.12);
  Color get accentLine => accent.withOpacity(0.42);
  Color get successSoft => success.withOpacity(0.15);
  Color get warningSoft => warning.withOpacity(0.15);
  Color get dangerSoft => danger.withOpacity(0.15);
  Color get infoSoft => info.withOpacity(0.16);

  /// Re-tint the accent to a connection color (mirrors tintVars()).
  SpColors withAccent(Color? hex) {
    if (hex == null) return this;
    return _copy(accent: hex, accent2: _shade(hex, dark ? -18 : -24));
  }

  SpColors _copy({Color? accent, Color? accent2}) => SpColors(
        dark: dark,
        bg: bg, surface: surface, surface2: surface2, surface3: surface3, surface4: surface4,
        border: border, border2: border2, borderStrong: borderStrong,
        text: text, text2: text2, text3: text3, text4: text4,
        accent: accent ?? this.accent, accent2: accent2 ?? this.accent2, accentInk: accentInk,
        success: success, warning: warning, danger: danger, info: info,
        lime: lime, limeInk: limeInk, cyan: cyan,
        synKw: synKw, synStr: synStr, synNum: synNum, synFn: synFn, synPunc: synPunc, synComment: synComment,
        navBg: navBg, dot: dot, scrim: scrim,
      );

  static Color _shade(Color c, int amt) => Color.fromARGB(
        255,
        (c.red + amt).clamp(0, 255),
        (c.green + amt).clamp(0, 255),
        (c.blue + amt).clamp(0, 255),
      );

  static const darkTokens = SpColors(
    dark: true,
    bg: Color(0xFF161618),
    surface: Color(0xFF1F1F22),
    surface2: Color(0xFF27272B),
    surface3: Color(0xFF313137),
    surface4: Color(0xFF3C3C44),
    border: Color(0x17F3F1EB),
    border2: Color(0x24F3F1EB),
    borderStrong: Color(0x38F3F1EB),
    text: Color(0xFFF3F1EC),
    text2: Color(0xFFABA8A1),
    text3: Color(0xFF76746E),
    text4: Color(0xFF54524D),
    accent: Color(0xFF4361FF),
    accent2: Color(0xFF3149DC),
    accentInk: Color(0xFFFFFFFF),
    success: Color(0xFF6FCB4F),
    warning: Color(0xFFE0A93C),
    danger: Color(0xFFFF5A4D),
    info: Color(0xFF57C4E8),
    lime: Color(0xFFC2F042),
    limeInk: Color(0xFF1A2207),
    cyan: Color(0xFF57C4E8),
    synKw: Color(0xFF8AB6FF),
    synStr: Color(0xFF9BE37C),
    synNum: Color(0xFFFFB871),
    synFn: Color(0xFFD2A8FF),
    synPunc: Color(0xFF97948C),
    synComment: Color(0xFF6A6760),
    navBg: Color(0xE6141416),
    dot: Color(0x0FFFFFFF),
    scrim: Color(0x9E040507),
  );

  static const lightTokens = SpColors(
    dark: false,
    bg: Color(0xFFEAE8E2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF4F2EC),
    surface3: Color(0xFFE7E4DC),
    surface4: Color(0xFFDAD6CC),
    border: Color(0x141C1A16),
    border2: Color(0x1F1C1A16),
    borderStrong: Color(0x331C1A16),
    text: Color(0xFF1C1B19),
    text2: Color(0xFF5E5C56),
    text3: Color(0xFF8C8980),
    text4: Color(0xFFB2AEA4),
    accent: Color(0xFF3551E5),
    accent2: Color(0xFF2A41C2),
    accentInk: Color(0xFFFFFFFF),
    success: Color(0xFF3F9D5A),
    warning: Color(0xFFB27C18),
    danger: Color(0xFFE1463A),
    info: Color(0xFF2197C0),
    lime: Color(0xFFBDEA34),
    limeInk: Color(0xFF20290A),
    cyan: Color(0xFF2197C0),
    synKw: Color(0xFF2A50D8),
    synStr: Color(0xFF1E8E4A),
    synNum: Color(0xFFB5510A),
    synFn: Color(0xFF8438C9),
    synPunc: Color(0xFF6B7280),
    synComment: Color(0xFF9AA0A8),
    navBg: Color(0xE6FFFFFF),
    dot: Color(0x141C1A16),
    scrim: Color(0x66282622),
  );

  static SpColors of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SpThemeScope>()!.colors;
  }
}

/// Inherited scope exposing the active [SpColors].
class SpThemeScope extends InheritedWidget {
  final SpColors colors;
  const SpThemeScope({super.key, required this.colors, required super.child});

  @override
  bool updateShouldNotify(SpThemeScope oldWidget) => oldWidget.colors != colors;
}

/// Color tags used by connections (TAG_COLORS).
const Map<String, Color> kTagColors = {
  'blue': Color(0xFF4361FF),
  'lime': Color(0xFF9FCF2E),
  'coral': Color(0xFFFF5A4D),
  'pink': Color(0xFFEC5FA8),
  'tan': Color(0xFFC9A574),
  'cyan': Color(0xFF3FB3D8),
  'violet': Color(0xFFA78BFA),
  'slate': Color(0xFF7C8AA0),
};

/// Relation line colors for the ER diagram.
Map<String, Color> relColor(SpColors c) => {
      'accent': c.accent,
      'warn': c.warning,
      'info': c.info,
      'lime': const Color(0xFF9FCF2E),
      'violet': const Color(0xFFA78BFA),
      'pink': const Color(0xFFEC5FA8),
      'coral': const Color(0xFFFF5A4D),
      'fk': c.info,
    };

/// Sans (Hanken Grotesk) and mono (JetBrains Mono) text helpers — bundled fonts.
TextStyle sans({double size = 14, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) =>
    TextStyle(fontFamily: _sans, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

TextStyle mono({double size = 13, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) =>
    TextStyle(fontFamily: _mono, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

ThemeData buildTheme(SpColors c) {
  final base = c.dark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    colorScheme: (c.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: c.accent,
      surface: c.surface,
    ),
    textTheme: base.textTheme.apply(fontFamily: _sans, bodyColor: c.text, displayColor: c.text),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
