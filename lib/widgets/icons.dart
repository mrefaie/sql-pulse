// SQL Pulse — icon name → Material icon mapping (mirrors the prototype's Lucide set).
import 'package:flutter/material.dart';

const Map<String, IconData> _iconMap = {
  'database': Icons.storage_rounded,
  'table': Icons.grid_on_rounded,
  'rows': Icons.table_rows_rounded,
  'columns': Icons.view_column_rounded,
  'key': Icons.vpn_key_rounded,
  'search': Icons.search_rounded,
  'play': Icons.play_arrow_rounded,
  'terminal': Icons.terminal_rounded,
  'code': Icons.code_rounded,
  'branch': Icons.account_tree_rounded,
  'clock': Icons.schedule_rounded,
  'history': Icons.history_rounded,
  'shield': Icons.shield_rounded,
  'plus': Icons.add_rounded,
  'minus': Icons.remove_rounded,
  'chevR': Icons.chevron_right_rounded,
  'chevD': Icons.keyboard_arrow_down_rounded,
  'arrowL': Icons.arrow_back_rounded,
  'x': Icons.close_rounded,
  'check': Icons.check_rounded,
  'trash': Icons.delete_outline_rounded,
  'filter': Icons.filter_alt_rounded,
  'fx': Icons.functions_rounded,
  'zap': Icons.bolt_rounded,
  'more': Icons.more_vert_rounded,
  'lock': Icons.lock_rounded,
  'network': Icons.lan_rounded,
  'alert': Icons.warning_amber_rounded,
  'info': Icons.info_outline_rounded,
  'eye': Icons.visibility_rounded,
  'wrench': Icons.build_rounded,
  'chart': Icons.bar_chart_rounded,
  'logout': Icons.logout_rounded,
  'refresh': Icons.refresh_rounded,
  'scan': Icons.crop_free_rounded,
  'sliders': Icons.tune_rounded,
  'folder': Icons.folder_rounded,
  'bell': Icons.notifications_rounded,
  'cog': Icons.settings_rounded,
  'gauge': Icons.speed_rounded,
  'grid': Icons.grid_view_rounded,
  'link': Icons.link_rounded,
  'dotgrid': Icons.scatter_plot_rounded,
  'spark': Icons.auto_awesome_rounded,
  'party': Icons.celebration_rounded,
  'bookmark': Icons.bookmark_rounded,
  'download': Icons.download_rounded,
  'share': Icons.share_rounded,
  'copy': Icons.copy_rounded,
  'save': Icons.save_rounded,
  'rerun': Icons.replay_rounded,
  'warn2': Icons.warning_amber_rounded,
  'fingerprint': Icons.fingerprint_rounded,
  'faceid': Icons.face_rounded,
  'backspace': Icons.backspace_outlined,
  'unlock': Icons.lock_open_rounded,
  'eyeoff': Icons.visibility_off_rounded,
  'layers': Icons.layers_rounded,
  'arrowR2': Icons.arrow_forward_rounded,
  'diff': Icons.difference_rounded,
  'gitcompare': Icons.compare_arrows_rounded,
  'sun': Icons.light_mode_rounded,
  'moon': Icons.dark_mode_rounded,
};

IconData spIconData(String name) => _iconMap[name] ?? Icons.circle_outlined;

class SpIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const SpIcon(this.name, {super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(spIconData(name), size: size, color: color ?? IconTheme.of(context).color);
  }
}
