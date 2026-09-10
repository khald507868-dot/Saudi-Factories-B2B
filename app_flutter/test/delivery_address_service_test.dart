import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saudi_factories/services/delivery_address_service.dart';

const _alice = '10000000-0000-4000-8000-000000000001';
const _bob = '10000000-0000-4000-8000-000000000002';
const _first = '20000000-0000-4000-8000-000000000001';
const _second = '20000000-0000-4000-8000-000000000002';

DeliveryAddress _address([String id = _first]) => DeliveryAddress(
  id: id,
  label: '  المنزل  ',
  addressLine: '  الرياض، طريق الملك فهد  ',
  latitude: 24.7,
  longitude: 46.7,
  building: ' 8 ',
  floor: ' 2 ',
  apartment: ' 4 ',
  notes: '  بجوار المدخل  ',
);

Map<String, dynamic> _row(
  DeliveryAddress address,
  String uid, {
  bool selected = true,
}) => {
  ...address.toJson(),
  'user_id': uid,
  'address_line': address.addressLine,
  'is_default': selected,
};

Matcher _error(String code) =>
    isA<DeliveryAddressException>().having((error) => error.code, 'code', code);

http.Response _json(http.Request request, Object value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) {
  final client = SupabaseClient(
    'https://delivery-addresses-test.invalid',
    'test-public-key',
    httpClient: MockClient(handler),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  addTearDown(client.dispose);
  return client;
}

DeliveryAddressService _store({
  ValueNotifier<String?>? user,
  SupabaseClient? client,
  Future<bool> Function(SharedPreferences, String, String)? writeString,
}) {
  final service = DeliveryAddressService.forTesting(
    preferences: SharedPreferences.getInstance,
    userId: () => user?.value,
    authChanges: user,
    client: client,
    writeString: writeString,
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'نموذج العنوان يحفظ التفاصيل ويمنع الإحداثيات أو الحقول غير الصالحة',
    () {
      final address = _address();
      expect(address.label, 'المنزل');
      expect(address.floor, '2');
      expect(
        DeliveryAddress.fromJson(address.toJson()).toJson(),
        address.toJson(),
      );
      expect(address.copyWith(notes: '').notes, '');
      for (final latitude in [double.nan, double.infinity, -91.0, 91.0]) {
        expect(
          () => address.copyWith(latitude: latitude),
          throwsA(_error('delivery_invalid_location')),
        );
      }
      expect(
        () => address.copyWith(longitude: 181),
        throwsA(_error('delivery_invalid_location')),
      );
      for (final label in ['', '   ', 'x' * 61]) {
        expect(
          () => address.copyWith(label: label),
          throwsA(_error('delivery_invalid_address')),
        );
      }
    },
  );

  test(
    'الزائر يحفظ ويختار ويحذف عنوانه ويستعيد الاختيار بعد إعادة التشغيل',
    () async {
      final first = _store();
      await first.start();
      await first.save(_address());
      await first.save(_address(_second));
      await first.select(_first);
      expect(() => first.addresses.clear(), throwsUnsupportedError);

      final restarted = _store();
      await restarted.start();
      expect(restarted.addresses.length, 2);
      expect(restarted.selected?.id, _first);
      await restarted.remove(_first);
      expect(restarted.selected?.id, _second);
      await restarted.remove(_second);
      expect(restarted.selected, isNull);
      await first.reload();
      expect(first.addresses, isEmpty);
    },
  );

  test('فشل الكتابة المحلية لا يعرض نجاحاً ولا يفقد الاختيار السابق', () async {
    var fail = false;
    final service = _store(
      writeString: (preferences, key, value) async =>
          fail ? false : preferences.setString(key, value),
    );
    await service.start();
    await service.save(_address());
    fail = true;
    await expectLater(
      service.save(_address(_second)),
      throwsA(_error('delivery_save_failed')),
    );
    expect(service.addresses.length, 1);
    expect(service.selected?.id, _first);
    await service.reload();
    expect(service.addresses.length, 1);
    fail = false;
    await service.save(_address(_second));
    expect(service.selected?.id, _second);
  });

  test('عمليات الحفظ المتزامنة متسلسلة ولا تسقط عنواناً', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var writes = 0;
    final service = _store(
      writeString: (preferences, key, value) async {
        writes++;
        if (writes == 1) {
          entered.complete();
          await release.future;
        }
        return preferences.setString(key, value);
      },
    );
    await service.start();
    final firstSave = service.save(_address());
    final secondSave = service.save(_address(_second));
    await entered.future;
    expect(writes, 1);
    release.complete();
    await Future.wait([firstSave, secondSave]);
    expect(service.addresses.map((address) => address.id), [_first, _second]);
    expect(service.selected?.id, _second);
  });

  test(
    'حساب المستخدم يستعيد العناوين والاختيار من الخادم على جهاز آخر',
    () async {
      final user = ValueNotifier<String?>(_alice);
      addTearDown(user.dispose);
      var rows = <Map<String, dynamic>>[];
      final rpcNames = <String>[];
      final client = _client((request) async {
        if (request.method == 'GET') {
          expect(request.url.queryParameters['user_id'], 'eq.$_alice');
          return _json(request, rows);
        }
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        expect(params['p_expected_user_id'], _alice);
        final name = request.url.path.split('/').last;
        rpcNames.add(name);
        if (name == 'save_delivery_address') {
          final saved = Map<String, dynamic>.from(params['p_address'] as Map);
          expect(saved['label'], 'المنزل');
          expect(saved.containsKey('user_id'), isFalse);
          for (final row in rows) {
            row['is_default'] = false;
          }
          rows.add({...saved, 'user_id': _alice, 'is_default': true});
        } else if (name == 'select_delivery_address') {
          for (final row in rows) {
            row['is_default'] = row['id'] == params['p_id'];
          }
        } else {
          rows.removeWhere((row) => row['id'] == params['p_id']);
          if (rows.isNotEmpty) rows.first['is_default'] = true;
        }
        return _json(request, rows);
      });
      final deviceOne = _store(user: user, client: client);
      await deviceOne.start();
      await deviceOne.save(_address());
      await deviceOne.save(_address(_second));
      await deviceOne.select(_first);
      final deviceTwo = _store(user: user, client: client);
      await deviceTwo.start();
      expect(deviceTwo.selected?.id, _first);
      expect(deviceTwo.addresses.length, 2);
      await deviceTwo.remove(_first);
      await deviceOne.reload();
      expect(deviceOne.selected?.id, _second);
      expect(rpcNames, [
        'save_delivery_address',
        'save_delivery_address',
        'select_delivery_address',
        'delete_delivery_address',
      ]);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('غياب جدول الخادم لا يتحول إلى حفظ محلي للحساب', () async {
    final user = ValueNotifier<String?>(_alice);
    addTearDown(user.dispose);
    var requests = 0;
    final client = _client((request) async {
      requests++;
      return _json(request, {'message': 'missing table', 'code': '42P01'}, 404);
    });
    final service = _store(user: user, client: client);
    await service.start();
    expect(service.error, 'delivery_load_failed');
    await expectLater(
      service.save(_address()),
      throwsA(_error('delivery_load_failed')),
    );
    expect(service.addresses, isEmpty);
    expect(requests, 1);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('فشل RPC يحفظ الحالة السابقة والمحاولة التالية تنجح', () async {
    final user = ValueNotifier<String?>(_alice);
    addTearDown(user.dispose);
    var fail = true;
    final client = _client((request) async {
      if (request.method == 'GET') {
        return _json(request, [_row(_address(), _alice)]);
      }
      if (fail) {
        return _json(request, {
          'message': 'network failed',
          'code': 'XX000',
        }, 400);
      }
      return _json(request, [
        _row(_address(), _alice, selected: false),
        _row(_address(_second), _alice),
      ]);
    });
    final service = _store(user: user, client: client);
    await service.start();
    await expectLater(
      service.save(_address(_second)),
      throwsA(_error('delivery_save_failed')),
    );
    expect(service.selected?.id, _first);
    expect(service.addresses.length, 1);
    fail = false;
    await service.save(_address(_second));
    expect(service.selected?.id, _second);
    expect(service.error, isNull);
  });

  test('تبديل الحساب يحجب العناوين فوراً ويتجاهل رد التحميل المتأخر', () async {
    final user = ValueNotifier<String?>(_alice);
    addTearDown(user.dispose);
    final entered = Completer<void>();
    final release = Completer<void>();
    final client = _client((request) async {
      if (request.url.queryParameters['user_id'] == 'eq.$_alice') {
        entered.complete();
        await release.future;
        return _json(request, [_row(_address(), _alice)]);
      }
      return _json(request, [_row(_address(_second), _bob)]);
    });
    final service = _store(user: user, client: client);
    final starting = service.start();
    await entered.future;
    user.value = _bob;
    expect(service.addresses, isEmpty);
    expect(service.selected, isNull);
    release.complete();
    await starting;
    await service.reload();
    expect(service.addresses.map((address) => address.id), [_second]);
    expect(service.selected?.id, _second);
  });

  test('رد حفظ الحساب السابق لا يظهر للحساب الجديد ولا يعلن نجاحاً', () async {
    final user = ValueNotifier<String?>(_alice);
    addTearDown(user.dispose);
    final entered = Completer<void>();
    final release = Completer<void>();
    final client = _client((request) async {
      if (request.method == 'GET') return _json(request, <Object>[]);
      expect(jsonDecode(request.body)['p_expected_user_id'], _alice);
      entered.complete();
      await release.future;
      return _json(request, [_row(_address(), _alice)]);
    });
    final service = _store(user: user, client: client);
    await service.start();
    final saving = expectLater(
      service.save(_address()),
      throwsA(_error('delivery_session_changed')),
    );
    await entered.future;
    user.value = _bob;
    expect(service.addresses, isEmpty);
    release.complete();
    await saving;
    await service.reload();
    expect(service.addresses, isEmpty);
    expect(service.selected, isNull);
  });

  test('عناوين الزائر لا تنتقل إلى حساب ولا تتبدل ببياناته', () async {
    final user = ValueNotifier<String?>(null);
    addTearDown(user.dispose);
    final client = _client(
      (request) async => _json(request, [_row(_address(_second), _alice)]),
    );
    final service = _store(user: user, client: client);
    await service.start();
    await service.save(_address());
    user.value = _alice;
    expect(service.selected, isNull);
    await service.reload();
    expect(service.selected?.id, _second);
    user.value = null;
    expect(service.selected, isNull);
    await service.reload();
    expect(service.selected?.id, _first);
  });

  test('يرفض رد الخادم الذي يخلط عناوين حسابين', () async {
    final user = ValueNotifier<String?>(_alice);
    addTearDown(user.dispose);
    final client = _client(
      (request) async => _json(request, [
        _row(_address(), _alice),
        _row(_address(_second), _bob),
      ]),
    );
    final service = _store(user: user, client: client);
    await service.start();
    expect(service.error, 'delivery_load_failed');
    expect(service.addresses, isEmpty);
  });
}
