import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// 촬영 장소 지도 팝업 (OpenStreetMap 타일, 키 필요 없음). 가운데 주황 핀이 촬영 위치.
Future<void> showPhotoMap(
  BuildContext context, {
  required double lat,
  required double lng,
  required String title,
  String? address,
}) => showSnapDialog<void>(
  context: context,
  barrierColor: const Color(0x66000000),
  builder: (ctx) =>
      _MapDialog(lat: lat, lng: lng, title: title, address: address),
);

class _MapDialog extends StatelessWidget {
  const _MapDialog({
    required this.lat,
    required this.lng,
    required this.title,
    this.address,
  });
  final double lat;
  final double lng;
  final String title;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final point = LatLng(lat, lng);
    return Dialog(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SnapIcon('pin', size: 22, color: c.pri),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        if (address != null && address!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              address!,
                              style: TextStyle(fontSize: 14, color: c.mute),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: SnapIcon('close', size: 22, color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 340,
                    child: Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: point,
                            initialZoom: 16,
                            minZoom: 4,
                            maxZoom: 19,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.snapback.snapbackApp',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: point,
                                  width: 30,
                                  height: 30,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c.pri,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x40000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // OpenStreetMap 이용 조건: 지도 위 출처 표시
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCCFFFFFF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '© OpenStreetMap',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
