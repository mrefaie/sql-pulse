// SQL Pulse — app entry, theming, and root routing.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/store.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'screens/connection_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const SqlPulseApp()));
}

class SqlPulseApp extends StatelessWidget {
  const SqlPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.select<AppState, String>((s) => s.theme);
    final base = theme == 'dark' ? SpColors.darkTokens : SpColors.lightTokens;
    return SpThemeScope(
      colors: base,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SQL Pulse',
        theme: buildTheme(base),
        home: const RootView(),
      ),
    );
  }
}

/// Routes between lock / connection / workspace. Responsive across phone,
/// tablet, and desktop: full-bleed on small screens, a centered focused panel
/// (no fake device frame) on wide screens so the layout stays comfortable.
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final base = state.theme == 'dark' ? SpColors.darkTokens : SpColors.lightTokens;

    Widget content;
    if (state.locked) {
      content = const LockScreen();
    } else if (state.screen == 'connect') {
      content = const ConnectionScreen();
    } else {
      content = const Workspace();
    }

    return SpThemeScope(
      colors: base,
      child: Material(
        color: base.bg,
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Breakpoints: phones full-bleed; tablets/desktop get a centered panel.
          final wide = w >= 720;
          if (!wide) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(),
              child: content,
            );
          }
          final centeredW = w < 880 ? w : 880.0;
          final panelH = (h - 40).clamp(0.0, double.infinity);
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.1),
                radius: 1.2,
                colors: base.dark ? const [Color(0xFF242427), Color(0xFF0E0E10)] : const [Color(0xFFF2F0EA), Color(0xFFD9D7D0)],
                stops: const [0, 0.75],
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: centeredW,
              height: panelH,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: base.bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: base.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(base.dark ? 0.45 : 0.16), blurRadius: 70, offset: const Offset(0, 30))],
              ),
              // Inner MediaQuery so SafeArea/insets reflect the panel, not the OS window.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
                child: content,
              ),
            ),
          );
        }),
      ),
    );
  }
}
