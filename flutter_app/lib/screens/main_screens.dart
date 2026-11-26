import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../models/photo_album.dart';
import '../models/photo_item.dart';
import '../services/recap.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/pin_pad.dart';
import '../widgets/recap_card.dart';
import '../widgets/snap_runner.dart';
import '../widgets/map_popup.dart';
import '../widgets/share_photo.dart';
import 'record_screens.dart';

// index.html(2aslx-patch-1) 의 섹션 5~15 + Flutter 추가 화면(16 앨범 상세).
// 화면별 파일은 screens/main/*.dart (같은 라이브러리의 part — 비공개 위젯을 서로 그대로 쓴다).

part 'main/home_screen.dart';
part 'main/photo_detail_screen.dart';
part 'main/memories_screen.dart';
part 'main/album_screens.dart';
part 'main/settings_screen.dart';
part 'main/search_screen.dart';
part 'main/recap_screens.dart';
