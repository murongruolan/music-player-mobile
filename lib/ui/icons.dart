// 图标映射：原型 icons.js 的名字 → Material Rounded 图标。
import 'package:flutter/material.dart';

const _map = <String, IconData>{
  'compass': Icons.explore_outlined, 'search': Icons.search_rounded, 'sun': Icons.wb_sunny_outlined,
  'library': Icons.library_music_outlined, 'user': Icons.person_outline_rounded, 'play': Icons.play_arrow_rounded,
  'pause': Icons.pause_rounded, 'next': Icons.skip_next_rounded, 'prev': Icons.skip_previous_rounded,
  'shuffle': Icons.shuffle_rounded, 'repeat': Icons.repeat_rounded, 'repeat1': Icons.repeat_one_rounded,
  'order': Icons.trending_flat_rounded, 'queue': Icons.queue_music_rounded, 'heart': Icons.favorite_border_rounded,
  'heartf': Icons.favorite_rounded, 'more': Icons.more_horiz_rounded, 'morev': Icons.more_vert_rounded,
  'down': Icons.keyboard_arrow_down_rounded, 'up': Icons.keyboard_arrow_up_rounded, 'left': Icons.arrow_back_ios_new_rounded,
  'right': Icons.chevron_right_rounded, 'close': Icons.close_rounded, 'download': Icons.download_rounded,
  'share': Icons.ios_share_rounded, 'moon': Icons.dark_mode_outlined, 'sliders': Icons.tune_rounded,
  'cast': Icons.cast_rounded, 'lyric': Icons.lyrics_outlined, 'quote': Icons.format_quote_rounded, 'mic': Icons.mic_none_rounded,
  'gear': Icons.settings_outlined, 'palette': Icons.palette_outlined, 'check': Icons.check_rounded,
  'refresh': Icons.refresh_rounded, 'trash': Icons.delete_outline_rounded, 'drag': Icons.drag_indicator_rounded,
  'scan': Icons.qr_code_scanner_rounded, 'cloud': Icons.cloud_outlined, 'shield': Icons.verified_user_outlined,
  'info': Icons.info_outline_rounded, 'bell': Icons.notifications_none_rounded, 'chart': Icons.bar_chart_rounded,
  'folder': Icons.folder_outlined, 'link': Icons.link_rounded, 'phone': Icons.smartphone_rounded, 'tv': Icons.tv_rounded,
  'mail': Icons.mail_outline_rounded, 'lock': Icons.lock_outline_rounded, 'eye': Icons.visibility_outlined,
  'eyeoff': Icons.visibility_off_outlined, 'globe': Icons.public_rounded, 'wave': Icons.graphic_eq_rounded,
  'speed': Icons.speed_rounded, 'sparkle': Icons.auto_awesome_outlined, 'crown': Icons.workspace_premium_outlined,
  'vinyl': Icons.album_outlined, 'copy': Icons.copy_rounded, 'bug': Icons.bug_report_outlined, 'code': Icons.code_rounded,
  'logout': Icons.logout_rounded, 'volume': Icons.volume_up_rounded, 'album': Icons.album_rounded, 'font': Icons.text_fields_rounded,
  'grid': Icons.grid_view_rounded, 'bluetooth': Icons.bluetooth_rounded, 'layers': Icons.layers_outlined, 'key': Icons.key_rounded,
  'clock': Icons.schedule_rounded, 'history': Icons.history_rounded, 'zap': Icons.bolt_rounded, 'flame': Icons.local_fire_department_outlined,
  'filter': Icons.filter_list_rounded, 'sort': Icons.sort_rounded, 'edit': Icons.edit_outlined, 'wifi': Icons.wifi_rounded,
  'hd': Icons.high_quality_outlined, 'car': Icons.directions_car_outlined, 'star': Icons.star_outline_rounded,
  'ext': Icons.open_in_new_rounded, 'plus': Icons.add_rounded, 'video': Icons.videocam_outlined, 'trend': Icons.trending_up_rounded,
  'arrowUL': Icons.north_west_rounded, 'timer': Icons.bedtime_outlined, 'calendar': Icons.calendar_today_outlined,
  'image': Icons.image_outlined, 'paste': Icons.content_paste_rounded, 'qr': Icons.qr_code_2_rounded, 'device': Icons.devices_rounded,
  'speaker': Icons.speaker_rounded, 'battery': Icons.battery_charging_full_rounded, 'storage': Icons.storage_rounded,
  'radar': Icons.radar_rounded, 'mood': Icons.mood_rounded, 'nodislike': Icons.thumb_down_off_alt_rounded,
};

IconData ic(String name) => _map[name] ?? Icons.circle_outlined;
