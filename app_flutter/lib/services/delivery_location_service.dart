import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// موقع اختاره المستخدم؛ الإحداثيات لا تعتمد على نجاح قراءة اسم الشارع.
class DeliveryLocation {
  const DeliveryLocation({
    required this.latitude,
    required this.longitude,
    this.addressLine = '',
    this.title = '',
  });

  final double latitude;
  final double longitude;
  final String addressLine;
  final String title;

  static bool validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  String get coordinates =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

class DeliveryLocationException implements Exception {
  const DeliveryLocationException();
}

/// بحث صريح وخدمة قراءة عنوان مع ذاكرة مؤقتة ومعدل طلبات محدود.
/// يمكن توجيهها إلى خادم Photon خاص دون تعديل الواجهة.
class DeliveryLocationService {
  DeliveryLocationService({
    http.Client? client,
    String baseUrl = const String.fromEnvironment(
      'SF_GEOCODING_BASE_URL',
      defaultValue: 'https://photon.komoot.io',
    ),
    this.requestInterval = const Duration(seconds: 1),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl = Uri.parse(baseUrl);

  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUrl;
  final Duration requestInterval;
  final Map<Uri, List<DeliveryLocation>> _cache = {};
  final Map<Uri, Future<List<DeliveryLocation>>> _pending = {};
  final Map<Uri, List<bool Function()?>> _currentChecks = {};
  Future<void> _queue = Future<void>.value();
  DateTime? _lastRequest;
  bool _disposed = false;

  Future<List<DeliveryLocation>> search(
    String query, {
    required double latitude,
    required double longitude,
    String language = 'ar',
    bool Function()? isCurrent,
  }) async {
    final clean = query.trim();
    if (clean.length < 2) return const [];
    _validateCoordinates(latitude, longitude);
    return _get('api/', {
      'q': clean,
      'limit': '5',
      'lat': latitude.toStringAsFixed(4),
      'lon': longitude.toStringAsFixed(4),
      if (language != 'ar') 'lang': 'en',
    }, isCurrent: isCurrent);
  }

  Future<DeliveryLocation> reverse({
    required double latitude,
    required double longitude,
    String language = 'ar',
    bool Function()? isCurrent,
  }) async {
    _validateCoordinates(latitude, longitude);
    final results = await _get('reverse/', {
      'lat': latitude.toStringAsFixed(5),
      'lon': longitude.toStringAsFixed(5),
      'limit': '1',
      if (language != 'ar') 'lang': 'en',
    }, isCurrent: isCurrent);
    final description = results.firstOrNull;
    // النتيجة قد تكون أقرب مبنى، لذلك نحفظ نقطة الدبوس الأصلية دائمًا.
    return DeliveryLocation(
      latitude: latitude,
      longitude: longitude,
      title: description?.title ?? '',
      addressLine: description?.addressLine ?? '',
    );
  }

  static void _validateCoordinates(double latitude, double longitude) {
    if (!DeliveryLocation.validCoordinates(latitude, longitude)) {
      throw ArgumentError('Invalid delivery coordinates');
    }
  }

  Future<List<DeliveryLocation>> _get(
    String endpoint,
    Map<String, String> query, {
    bool Function()? isCurrent,
  }) {
    if (_disposed) return Future.error(const DeliveryLocationException());
    final basePath = _baseUrl.path.replaceFirst(RegExp(r'/$'), '');
    final uri = _baseUrl.replace(
      path: '$basePath/$endpoint',
      queryParameters: query,
    );
    final cached = _cache[uri];
    if (cached != null) return Future.value(cached);
    final pending = _pending[uri];
    if (pending != null) {
      _currentChecks[uri]!.add(isCurrent);
      return pending;
    }
    final checks = _currentChecks[uri] = [isCurrent];
    bool hasCurrentCaller() => checks.any((check) => check == null || check());

    final result = _queue.then((_) async {
      if (_disposed || !hasCurrentCaller()) {
        throw const DeliveryLocationException();
      }
      final last = _lastRequest;
      if (last != null) {
        final wait = requestInterval - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      if (_disposed || !hasCurrentCaller()) {
        throw const DeliveryLocationException();
      }
      _lastRequest = DateTime.now();
      try {
        final response = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw const DeliveryLocationException();
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map || decoded['features'] is! List) {
          throw const DeliveryLocationException();
        }
        final locations = <DeliveryLocation>[];
        for (final feature in decoded['features'] as List) {
          final location = _parseFeature(feature);
          if (location != null) locations.add(location);
        }
        final immutable = List<DeliveryLocation>.unmodifiable(locations);
        if (_cache.length >= 40) _cache.remove(_cache.keys.first);
        _cache[uri] = immutable;
        return immutable;
      } catch (_) {
        throw const DeliveryLocationException();
      }
    });
    _pending[uri] = result;
    _queue = result.then<void>(
      (_) {
        _pending.remove(uri);
        _currentChecks.remove(uri);
      },
      onError: (Object _) {
        _pending.remove(uri);
        _currentChecks.remove(uri);
      },
    );
    return result;
  }

  static DeliveryLocation? _parseFeature(dynamic feature) {
    if (feature is! Map) return null;
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    if (geometry is! Map || properties is! Map) return null;
    final coordinates = geometry['coordinates'];
    if (geometry['type'] != 'Point' ||
        coordinates is! List ||
        coordinates.length < 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      return null;
    }
    final latitude = (coordinates[1] as num).toDouble();
    final longitude = (coordinates[0] as num).toDouble();
    if (!DeliveryLocation.validCoordinates(latitude, longitude)) return null;
    String value(String key) =>
        properties[key] is String ? (properties[key] as String).trim() : '';
    final street = [
      value('housenumber'),
      value('street'),
    ].where((part) => part.isNotEmpty).join(' ');
    final parts = <String>{
      value('name'),
      street,
      value('district'),
      value('city'),
      value('state'),
      value('postcode'),
      value('country'),
    }..remove('');
    return DeliveryLocation(
      latitude: latitude,
      longitude: longitude,
      title: value('name').isNotEmpty ? value('name') : value('street'),
      addressLine: parts.join('، '),
    );
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    if (_ownsClient) _client.close();
  }
}
