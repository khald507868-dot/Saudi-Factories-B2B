import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saudi_factories/services/delivery_location_service.dart';

Map<String, Object> _feature({
  double latitude = 24.72,
  double longitude = 46.67,
}) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [longitude, latitude],
  },
  'properties': {
    'name': 'مصنع الرياض',
    'street': 'شارع الصناعة',
    'housenumber': '25',
    'city': 'الرياض',
    'state': 'الرياض',
    'country': 'السعودية',
  },
};

http.Response _json(http.Request request, Object data, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test(
    'طلب أحدث لنفس النقطة يبقى صالحاً بعد إلغاء الطلب الذي اندمج معه',
    () async {
      var count = 0;
      final client = MockClient((request) async {
        count++;
        return _json(request, {
          'features': [_feature()],
        });
      });
      final service = DeliveryLocationService(client: client);
      addTearDown(service.dispose);
      addTearDown(client.close);
      final results = await Future.wait([
        service.reverse(
          latitude: 24.7,
          longitude: 46.6,
          isCurrent: () => false,
        ),
        service.reverse(latitude: 24.7, longitude: 46.6, isCurrent: () => true),
      ]);
      expect(results.last.title, 'مصنع الرياض');
      expect(count, 1);
    },
  );

  test(
    'الاختيار القديم لا يرسل طلبًا عند وصول دوره ولا يعطّل الاختيار الجديد',
    () async {
      var count = 0;
      final client = MockClient((request) async {
        count++;
        return _json(request, {
          'features': [_feature()],
        });
      });
      final service = DeliveryLocationService(client: client);
      addTearDown(service.dispose);
      addTearDown(client.close);
      await expectLater(
        service.reverse(
          latitude: 24.7,
          longitude: 46.6,
          isCurrent: () => false,
        ),
        throwsA(isA<DeliveryLocationException>()),
      );
      expect(count, 0);
      await service.reverse(latitude: 24.8, longitude: 46.6);
      expect(count, 1);
    },
  );

  test(
    'البحث يحفظ العربية ويقرأ ترتيب إحداثيات GeoJSON دون تكرار المدينة',
    () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return _json(request, {
          'features': [_feature()],
        });
      });
      final service = DeliveryLocationService(client: client);
      addTearDown(service.dispose);
      addTearDown(client.close);
      final results = await service.search(
        '  مصنع الرياض  ',
        latitude: 24.7,
        longitude: 46.6,
      );
      expect(requested.path, '/api/');
      expect(requested.queryParameters['q'], 'مصنع الرياض');
      expect(requested.queryParameters['lang'], isNull);
      expect(requested.queryParameters['limit'], '5');
      expect(results.single.latitude, 24.72);
      expect(results.single.longitude, 46.67);
      expect(results.single.title, 'مصنع الرياض');
      expect(
        results.single.addressLine,
        'مصنع الرياض، 25 شارع الصناعة، الرياض، السعودية',
      );
    },
  );

  test('قراءة العنوان تحفظ نقطة المستخدم حتى لو أقرب مبنى مختلف', () async {
    final client = MockClient(
      (request) async => _json(request, {
        'features': [_feature()],
      }),
    );
    final service = DeliveryLocationService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final location = await service.reverse(
      latitude: 24.7123456,
      longitude: 46.6123456,
    );
    expect(location.latitude, 24.7123456);
    expect(location.longitude, 46.6123456);
    expect(location.title, 'مصنع الرياض');
  });

  test('لا يخترع عنواناً عند خلو النتائج ويتجاهل الإحداثيات التالفة', () async {
    final client = MockClient(
      (request) async => _json(request, {
        'features': [
          _feature(latitude: 123),
          {
            'geometry': {
              'type': 'Point',
              'coordinates': ['bad', 24],
            },
            'properties': {},
          },
        ],
      }),
    );
    final service = DeliveryLocationService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    final location = await service.reverse(latitude: 24.7, longitude: 46.6);
    expect(location.addressLine, isEmpty);
    expect(location.title, isEmpty);
    expect(location.coordinates, '24.70000, 46.60000');
  });

  test('الطلبات المتزامنة والمتكررة تستخدم نفس النتيجة المحفوظة', () async {
    var count = 0;
    final client = MockClient((request) async {
      count++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return _json(request, {
        'features': [_feature()],
      });
    });
    final service = DeliveryLocationService(client: client);
    addTearDown(service.dispose);
    addTearDown(client.close);
    await Future.wait([
      service.reverse(latitude: 24.7, longitude: 46.6),
      service.reverse(latitude: 24.7, longitude: 46.6),
    ]);
    await service.reverse(latitude: 24.7, longitude: 46.6);
    expect(count, 1);
  });

  test('الخطأ لا يخزّن نتيجة فارغة ويقبل إعادة المحاولة', () async {
    var count = 0;
    final client = MockClient((request) async {
      count++;
      return count == 1
          ? _json(request, {'error': 'unavailable'}, status: 503)
          : _json(request, {
              'features': [_feature()],
            });
    });
    final service = DeliveryLocationService(
      client: client,
      requestInterval: Duration.zero,
    );
    addTearDown(service.dispose);
    addTearDown(client.close);
    await expectLater(
      service.reverse(latitude: 24.7, longitude: 46.6),
      throwsA(isA<DeliveryLocationException>()),
    );
    expect(
      (await service.reverse(latitude: 24.7, longitude: 46.6)).title,
      'مصنع الرياض',
    );
    expect(count, 2);
  });

  test(
    'التباعد بين الطلبات المختلفة محترم والإحداثيات غير الصالحة لا تُرسل',
    () async {
      final requests = <DateTime>[];
      final client = MockClient((request) async {
        requests.add(DateTime.now());
        return _json(request, {'features': []});
      });
      final service = DeliveryLocationService(
        client: client,
        requestInterval: const Duration(milliseconds: 60),
      );
      addTearDown(service.dispose);
      addTearDown(client.close);
      await Future.wait([
        service.reverse(latitude: 24.7, longitude: 46.6),
        service.reverse(latitude: 24.8, longitude: 46.6),
      ]);
      expect(
        requests[1].difference(requests[0]).inMilliseconds,
        greaterThanOrEqualTo(55),
      );
      await expectLater(
        service.reverse(latitude: double.nan, longitude: 46),
        throwsArgumentError,
      );
      expect(requests, hasLength(2));
    },
  );

  test(
    'الخادم قابل للتهيئة واللغة الإنجليزية صريحة والبحث القصير لا يرسل',
    () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return _json(request, {'features': []});
      });
      final service = DeliveryLocationService(
        client: client,
        baseUrl: 'https://geo.example.com/photon/',
      );
      addTearDown(service.dispose);
      addTearDown(client.close);
      expect(await service.search(' ', latitude: 24, longitude: 46), isEmpty);
      expect(requested, isNull);
      await service.search(
        'Riyadh',
        latitude: 24,
        longitude: 46,
        language: 'en',
      );
      expect(requested?.host, 'geo.example.com');
      expect(requested?.path, '/photon/api/');
      expect(requested?.queryParameters['lang'], 'en');
    },
  );
}
