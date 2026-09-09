import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/i18n_data.dart';
import '../core/theme.dart';
import '../pages/factories_page.dart';
import 'common.dart';

/// خريطة مناطق المملكة من نفس حدود OpenStreetMap المستخدمة في الموقع.
class FactoryMap extends StatefulWidget {
  const FactoryMap({super.key});
  @override
  State<FactoryMap> createState() => _FactoryMapState();
}

class _FactoryMapState extends State<FactoryMap> {
  late final Future<Map<String, dynamic>> _regions = rootBundle
      .loadString('assets/saudi_regions.json')
      .then((value) => (jsonDecode(value) as Map).cast<String, dynamic>());

  void _open(String region) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FactoriesPage(
        initialRegion: region,
        categoryLabel: context.i18n.regionName(region),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t('factory_map_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _regions,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SFStateView(message: context.t('fx_failed'));
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return SizedBox(
                height: 220,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final painter = SaudiRegionsPainter(snapshot.data!);
                    final size = Size(constraints.maxWidth, 220);
                    return InteractiveViewer(
                      maxScale: 5,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTapUp: (details) {
                            for (final region in painter.paths(size).entries) {
                              if (region.value.contains(
                                details.localPosition,
                              )) {
                                _open(region.key);
                                return;
                              }
                            }
                          },
                          child: CustomPaint(painter: painter, size: size),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.t('region_choose'),
              prefixIcon: const Icon(Icons.location_on_outlined, size: 19),
              filled: true,
              fillColor: SFColors.surfaceAlt,
            ),
            items: [
              for (final region in kRegionNames.keys)
                DropdownMenuItem(
                  value: region,
                  child: Text(context.i18n.regionName(region)),
                ),
            ],
            onChanged: (region) {
              if (region != null) _open(region);
            },
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: SFColors.muted2),
            onPressed: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text(
              '© OpenStreetMap · ODbL',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
}

class SaudiRegionsPainter extends CustomPainter {
  SaudiRegionsPainter(this.regions);
  final Map<String, dynamic> regions;
  Map<String, Path> paths(Size size) {
    final scale = (size.width / 22 < size.height / 17
        ? size.width / 22
        : size.height / 17);
    final left = (size.width - 22 * scale) / 2;
    final top = (size.height - 17 * scale) / 2;
    return {
      for (final region in regions.entries)
        region.key: _path(region.value as List, scale, left, top),
    };
  }

  Path _path(List rings, double scale, double left, double top) {
    final path = Path();
    for (final ring in rings) {
      final points = ring as List;
      for (var index = 0; index < points.length; index++) {
        final point = points[index] as List;
        final x = left + ((point[1] as num).toDouble() - 34) * scale;
        final y = top + (33 - (point[0] as num).toDouble()) * scale;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outlines = paths(size).values;
    for (final path in outlines) {
      canvas.drawPath(
        path,
        Paint()
          ..color = SFColors.midGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    for (final path in outlines) {
      canvas.drawPath(path, Paint()..color = const Color(0xFFD9E8DD));
      canvas.drawPath(
        path,
        Paint()
          ..color = SFColors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9,
      );
    }
  }

  @override
  bool shouldRepaint(SaudiRegionsPainter oldDelegate) =>
      oldDelegate.regions != regions;
}
