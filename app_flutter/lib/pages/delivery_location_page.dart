import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/delivery_location_service.dart';

/// خريطة مستقلة لعناوين التوصيل؛ لا تعيد خريطة مناطق المصانع للرئيسية.
class DeliveryLocationPage extends StatefulWidget {
  const DeliveryLocationPage({super.key, this.initialLocation});

  final DeliveryLocation? initialLocation;

  @override
  State<DeliveryLocationPage> createState() => _DeliveryLocationPageState();
}

class _DeliveryLocationPageState extends State<DeliveryLocationPage> {
  final _map = MapController();
  final _search = TextEditingController();
  final _service = DeliveryLocationService();
  var _tileProvider = NetworkTileProvider();
  Timer? _reverseTimer;
  late LatLng _point;
  late DeliveryLocation _location;
  late bool _hasSelection;
  List<DeliveryLocation>? _results;
  String? _searchError;
  String? _positionError;
  bool _searching = false;
  bool _readingAddress = false;
  bool _addressFailed = false;
  bool _locating = false;
  bool _tileFailed = false;
  bool _mapReady = false;
  int _tileVersion = 0;
  int _selectionVersion = 0;
  int _searchVersion = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLocation;
    _hasSelection = initial != null;
    // الرياض نقطة بدء فقط، ولا تُعرض على أنها الموقع الحالي للمستخدم.
    _location =
        initial ??
        const DeliveryLocation(latitude: 24.7136, longitude: 46.6753);
    _point = LatLng(_location.latitude, _location.longitude);
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
    _service.dispose();
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  void _pickPoint(LatLng point, {bool moveMap = false}) {
    if (!mounted) return;
    point = LatLng(
      point.latitude.clamp(-85, 85),
      point.longitude.clamp(-180, 180),
    );
    _reverseTimer?.cancel();
    final version = ++_selectionVersion;
    ++_searchVersion;
    setState(() {
      _point = point;
      _location = DeliveryLocation(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      _hasSelection = true;
      _results = null;
      _searching = false;
      _searchError = null;
      _positionError = null;
      _addressFailed = false;
      _readingAddress = true;
    });
    if (moveMap && _mapReady) _map.move(point, math.max(_map.camera.zoom, 15));
    final language = context.i18n.lang;
    _reverseTimer = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted || version != _selectionVersion) return;
      try {
        final result = await _service.reverse(
          latitude: point.latitude,
          longitude: point.longitude,
          language: language,
          isCurrent: () => mounted && version == _selectionVersion,
        );
        if (!mounted || version != _selectionVersion) return;
        setState(() {
          _location = result;
          _readingAddress = false;
          _addressFailed = result.addressLine.isEmpty;
        });
      } catch (_) {
        if (!mounted || version != _selectionVersion) return;
        setState(() {
          _readingAddress = false;
          _addressFailed = true;
        });
      }
    });
  }

  Future<void> _submitSearch() async {
    final query = _search.text.trim();
    if (query.length < 2) return;
    FocusScope.of(context).unfocus();
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _searchError = null;
      _results = null;
    });
    try {
      final results = await _service.search(
        query,
        latitude: _point.latitude,
        longitude: _point.longitude,
        language: context.i18n.lang,
        isCurrent: () => mounted && version == _searchVersion,
      );
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _searching = false;
        _results = results;
      });
    } catch (_) {
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _searching = false;
        _searchError = 'delivery_search_failed';
      });
    }
  }

  void _selectSearchResult(DeliveryLocation result) {
    _reverseTimer?.cancel();
    ++_selectionVersion;
    ++_searchVersion;
    setState(() {
      _point = LatLng(result.latitude, result.longitude);
      _location = result;
      _hasSelection = true;
      _results = null;
      _searching = false;
      _readingAddress = false;
      _addressFailed = result.addressLine.isEmpty;
      _positionError = null;
    });
    FocusScope.of(context).unfocus();
    if (_mapReady) _map.move(_point, 16);
  }

  Future<void> _locate() async {
    if (_locating) return;
    final version = _selectionVersion;
    setState(() {
      _locating = true;
      _positionError = null;
    });
    String? failure;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        failure = 'delivery_location_disabled';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          failure = 'delivery_location_denied';
        } else {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20),
            ),
          );
          if (!mounted) return;
          if (version == _selectionVersion) {
            _pickPoint(
              LatLng(position.latitude, position.longitude),
              moveMap: true,
            );
          }
        }
      }
    } catch (_) {
      failure = 'delivery_location_unavailable';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (version == _selectionVersion) _positionError = failure;
    });
  }

  Future<void> _enterCoordinates() async {
    final point = await showDialog<LatLng>(
      context: context,
      builder: (_) => _CoordinatesDialog(point: _hasSelection ? _point : null),
    );
    if (!mounted || point == null) return;
    _pickPoint(point, moveMap: true);
  }

  void _retryTiles() {
    setState(() {
      _tileFailed = false;
      _tileProvider = NetworkTileProvider();
      _tileVersion++;
    });
  }

  void _tileError() {
    if (_tileFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed) {
        setState(() {
          _tileFailed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t('delivery_choose_location'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        toolbarHeight: 52,
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _point,
                      initialZoom: _hasSelection ? 16 : 11,
                      minZoom: 3,
                      maxZoom: 19,
                      cameraConstraint: CameraConstraint.containCenter(
                        bounds: LatLngBounds(
                          const LatLng(-85, -180),
                          const LatLng(85, 180),
                        ),
                      ),
                      backgroundColor: SFColors.surfaceAlt,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onMapReady: () {
                        _mapReady = true;
                      },
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture && camera.center != _point) {
                          _pickPoint(camera.center);
                        }
                      },
                      onTap: (_, point) {
                        FocusScope.of(context).unfocus();
                        _pickPoint(point, moveMap: true);
                      },
                    ),
                    children: [
                      TileLayer(
                        key: ValueKey(_tileVersion),
                        tileProvider: _tileProvider,
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.saudifactories.saudi_factories',
                        maxNativeZoom: 19,
                        panBuffer: 0,
                        errorTileCallback: (_, _, _) => _tileError(),
                      ),
                    ],
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -23),
                        child: const Icon(
                          Icons.location_on,
                          size: 54,
                          color: SFColors.midGreen,
                          shadows: [Shadow(color: Colors.white, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                  if (constraints.maxHeight > 310 &&
                      _results == null &&
                      _searchError == null)
                    Positioned(
                      top: constraints.maxHeight / 2 - 99,
                      left: 34,
                      right: 34,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: SFColors.midGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              context.t(
                                _hasSelection
                                    ? 'delivery_map_hint'
                                    : 'delivery_default_map_hint',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (constraints.maxHeight > 230)
                    PositionedDirectional(
                      bottom: _tileFailed ? 106 : 34,
                      start: 14,
                      child: _MapButton(
                        tooltip: context.t(
                          _locating
                              ? 'delivery_locating'
                              : 'delivery_current_location',
                        ),
                        icon: Icons.my_location,
                        busy: _locating,
                        onPressed: _locating ? null : _locate,
                      ),
                    ),
                  if (constraints.maxHeight > 310)
                    PositionedDirectional(
                      bottom: _tileFailed ? 106 : 34,
                      end: 14,
                      child: Column(
                        children: [
                          _MapButton(
                            tooltip: context.t('delivery_zoom_in'),
                            icon: Icons.add,
                            onPressed: () {
                              if (_mapReady) {
                                _map.move(
                                  _map.camera.center,
                                  math.min(_map.camera.zoom + 1, 19),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 6),
                          _MapButton(
                            tooltip: context.t('delivery_zoom_out'),
                            icon: Icons.remove,
                            onPressed: () {
                              if (_mapReady) {
                                _map.move(
                                  _map.camera.center,
                                  math.max(_map.camera.zoom - 1, 3),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: .92),
                      child: InkWell(
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '© OpenStreetMap contributors · Photon',
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: SFColors.muted2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_tileFailed && constraints.maxHeight > 230)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 30,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.t('delivery_map_unavailable'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _retryTiles,
                                tooltip: context.t('app_retry'),
                                icon: const Icon(Icons.refresh, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 14,
                    left: 14,
                    right: 14,
                    child: _searchPanel(
                      math.max(48, math.min(230, constraints.maxHeight - 36)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!keyboard) _locationPanel(),
        ],
      ),
    );
  }

  Widget _searchPanel(double maximumHeight) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: Colors.black12,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maximumHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: TextField(
              key: const ValueKey('delivery-map-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submitSearch(),
              onChanged: (_) {
                ++_searchVersion;
                if (_results != null || _searching || _searchError != null) {
                  setState(() {
                    _results = null;
                    _searching = false;
                    _searchError = null;
                  });
                }
              },
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: context.t('delivery_search_address'),
                hintStyle: const TextStyle(fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                prefixIcon: IconButton(
                  onPressed: _searching ? null : _submitSearch,
                  tooltip: context.t('delivery_search_address'),
                  icon: const Icon(Icons.search),
                ),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),
          ),
          if (_searchError != null || _results != null)
            Flexible(
              child: _results?.isNotEmpty == true
                  ? ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _results!.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final result = _results![index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(
                            result.title.isNotEmpty
                                ? result.title
                                : context.t('delivery_selected_location'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            result.addressLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.t(
                                  _searchError ?? 'delivery_no_results',
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (_searchError != null)
                              IconButton(
                                onPressed: _submitSearch,
                                tooltip: context.t('app_retry'),
                                icon: const Icon(Icons.refresh),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ),
  );

  Widget _locationPanel() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('delivery_location'),
              style: const TextStyle(color: SFColors.muted2, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              _hasSelection
                  ? (_location.title.isNotEmpty
                        ? _location.title
                        : context.t('delivery_selected_location'))
                  : context.t('delivery_default_map_hint'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.3,
              ),
            ),
            if (_hasSelection) ...[
              const SizedBox(height: 4),
              if (_readingAddress)
                Text(
                  context.t('delivery_reading_address'),
                  style: const TextStyle(fontSize: 12, color: SFColors.muted2),
                )
              else if (_location.addressLine.isNotEmpty)
                Text(
                  _location.addressLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                )
              else
                Text(
                  _location.coordinates,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 13, color: SFColors.muted2),
                ),
              if (_addressFailed)
                Text(
                  context.t('delivery_address_unavailable'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: SFColors.muted2,
                    height: 1.3,
                  ),
                ),
            ],
            if (_positionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.t(_positionError!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: SFColors.danger,
                    height: 1.3,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const ValueKey('delivery-confirm-location'),
              onPressed: _hasSelection && !_locating
                  ? () => Navigator.of(context).pop(_location)
                  : null,
              child: Text(context.t('delivery_confirm_location')),
            ),
            TextButton(
              onPressed: _enterCoordinates,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(
                context.t('delivery_manual_coordinates'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: Colors.black12,
    borderRadius: BorderRadius.circular(12),
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: SFColors.darkGreen,
      icon: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 22),
    ),
  );
}

class _CoordinatesDialog extends StatefulWidget {
  const _CoordinatesDialog({this.point});
  final LatLng? point;

  @override
  State<_CoordinatesDialog> createState() => _CoordinatesDialogState();
}

class _CoordinatesDialogState extends State<_CoordinatesDialog> {
  late final _latitude = TextEditingController(
    text: widget.point?.latitude.toStringAsFixed(5) ?? '',
  );
  late final _longitude = TextEditingController(
    text: widget.point?.longitude.toStringAsFixed(5) ?? '',
  );
  bool _invalid = false;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _confirm() {
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    if (latitude == null ||
        longitude == null ||
        !DeliveryLocation.validCoordinates(latitude, longitude) ||
        latitude.abs() > 85) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    Navigator.pop(context, LatLng(latitude, longitude));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('delivery_manual_coordinates')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _latitude,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: context.t('delivery_latitude'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _longitude,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: context.t('delivery_longitude'),
            ),
          ),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                context.t('delivery_coordinates_invalid'),
                style: const TextStyle(color: SFColors.danger),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('msg_cancel')),
      ),
      TextButton(
        onPressed: _confirm,
        child: Text(context.t('delivery_confirm_location')),
      ),
    ],
  );
}
