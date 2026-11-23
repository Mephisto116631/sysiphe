import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/course.dart';

/// Carte OpenStreetMap avec le tracé de la course. Sans réseau, le fond de
/// carte reste gris mais le tracé est dessiné.
///
/// [follow] : la carte suit la dernière position (pendant la course).
class CourseMap extends StatefulWidget {
  final List<TracePoint> trace;
  final GpsPoint? position;
  final bool follow;

  const CourseMap(
      {super.key, required this.trace, this.position, this.follow = false});

  /// Fond de carte (désactivé dans les tests : pas de réseau).
  static bool tilesEnabled = true;

  @override
  State<CourseMap> createState() => _CourseMapState();
}

class _CourseMapState extends State<CourseMap> {
  final _ctrl = MapController();
  bool _ready = false;

  List<LatLng> get _points =>
      [for (final p in widget.trace) LatLng(p.lat, p.lng)];

  LatLng? get _here {
    final p = widget.position;
    if (p != null) return LatLng(p.lat, p.lng);
    final t = widget.trace;
    return t.isEmpty ? null : LatLng(t.last.lat, t.last.lng);
  }

  @override
  void didUpdateWidget(CourseMap old) {
    super.didUpdateWidget(old);
    final here = _here;
    if (widget.follow && _ready && here != null) {
      try {
        _ctrl.move(here, _ctrl.camera.zoom);
      } catch (_) {/* carte pas encore affichée */}
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    final here = _here;
    final fit = !widget.follow && pts.length >= 2
        ? CameraFit.coordinates(
            coordinates: pts,
            padding: const EdgeInsets.all(24),
            maxZoom: 17)
        : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: here ?? const LatLng(48.8566, 2.3522),
          initialZoom: here == null ? 5 : 16,
          initialCameraFit: fit,
          onMapReady: () => _ready = true,
          interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        ),
        children: [
          if (CourseMap.tilesEnabled)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sysiphe.app',
              maxNativeZoom: 19,
            ),
          if (pts.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                  points: pts,
                  strokeWidth: 5,
                  color: Colors.deepOrange,
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white),
            ]),
          if (here != null)
            MarkerLayer(markers: [
              Marker(
                point: here,
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ]),
          if (CourseMap.tilesEnabled)
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: Text('© OpenStreetMap',
                    style: TextStyle(fontSize: 9, color: Colors.black54)),
              ),
            ),
        ],
      ),
    );
  }
}
