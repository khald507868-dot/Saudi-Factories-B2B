import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

class DeliveryAddressException implements Exception {
  const DeliveryAddressException(this.code);

  final String code;

  @override
  String toString() => code;
}

@immutable
class DeliveryAddress {
  DeliveryAddress({
    required String id,
    required String label,
    required String addressLine,
    required this.latitude,
    required this.longitude,
    String building = '',
    String floor = '',
    String apartment = '',
    String notes = '',
  }) : id = _text(id, 128, required: true),
       label = _text(label, 60, required: true),
       addressLine = _text(addressLine, 500, required: true),
       building = _text(building, 80),
       floor = _text(floor, 40),
       apartment = _text(apartment, 40),
       notes = _text(notes, 500) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const DeliveryAddressException('delivery_invalid_location');
    }
  }

  final String id;
  final String label;
  final String addressLine;
  final double latitude;
  final double longitude;
  final String building;
  final String floor;
  final String apartment;
  final String notes;

  static String _text(String value, int maxLength, {bool required = false}) {
    final trimmed = value.trim();
    if ((required && trimmed.isEmpty) || trimmed.runes.length > maxLength) {
      throw const DeliveryAddressException('delivery_invalid_address');
    }
    return trimmed;
  }

  DeliveryAddress copyWith({
    String? id,
    String? label,
    String? addressLine,
    double? latitude,
    double? longitude,
    String? building,
    String? floor,
    String? apartment,
    String? notes,
  }) => DeliveryAddress(
    id: id ?? this.id,
    label: label ?? this.label,
    addressLine: addressLine ?? this.addressLine,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    building: building ?? this.building,
    floor: floor ?? this.floor,
    apartment: apartment ?? this.apartment,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'addressLine': addressLine,
    'latitude': latitude,
    'longitude': longitude,
    'building': building,
    'floor': floor,
    'apartment': apartment,
    'notes': notes,
  };

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) {
    String text(String key, {bool optional = false}) {
      final value = json[key];
      if (value == null && optional) return '';
      if (value is! String) {
        throw const DeliveryAddressException('delivery_invalid_address');
      }
      return value;
    }

    final latitude = json['latitude'];
    final longitude = json['longitude'];
    if (latitude is! num || longitude is! num) {
      throw const DeliveryAddressException('delivery_invalid_location');
    }
    return DeliveryAddress(
      id: text('id'),
      label: text('label'),
      addressLine: text('addressLine'),
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      building: text('building', optional: true),
      floor: text('floor', optional: true),
      apartment: text('apartment', optional: true),
      notes: text('notes', optional: true),
    );
  }
}

/// عناوين الحساب في Supabase، وعناوين الزائر على هذا الجهاز فقط.
class DeliveryAddressService extends ChangeNotifier {
  DeliveryAddressService._()
    : _preferences = SharedPreferences.getInstance,
      _userId = (() => AuthService.instance.user?.id),
      _authChanges = AuthService.instance,
      _client = (() => sb),
      _writeString = null;

  @visibleForTesting
  DeliveryAddressService.forTesting({
    required this._preferences,
    required this._userId,
    this._authChanges,
    SupabaseClient? client,
    this._writeString,
  }) : _client = (() => client ?? sb);

  static final DeliveryAddressService instance = DeliveryAddressService._();
  static const int maxAddresses = 20;

  final Future<SharedPreferences> Function() _preferences;
  final String? Function() _userId;
  final Listenable? _authChanges;
  final SupabaseClient Function() _client;
  final Future<bool> Function(SharedPreferences, String, String)? _writeString;

  Future<void> _queue = Future<void>.value();
  Future<void>? _startFuture;
  List<DeliveryAddress> _addresses = const [];
  String? _selectedId;
  String? _scope;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _started = false;
  bool _disposed = false;

  // نتحقق أيضاً عند القراءة كي لا يظهر عنوان حساب سابق أثناء تحميل الجلسة.
  List<DeliveryAddress> get addresses => _scope == _currentScope && !_disposed
      ? List<DeliveryAddress>.unmodifiable(_addresses)
      : const [];

  DeliveryAddress? get selected {
    for (final address in addresses) {
      if (address.id == _selectedId) return address;
    }
    return null;
  }

  bool get isLoading => _loading || _scope != _currentScope;
  String? get error => _scope == _currentScope ? _error : null;
  bool get isGuest => _userId() == null;
  String? get userId => _userId();

  static const _guestScope = 'sf_delivery_addresses_v1:guest';
  static const _userPrefix = 'sf_delivery_addresses_v1:user:';
  static const _columns =
      'id,user_id,label,address_line,latitude,longitude,building,floor,apartment,notes,is_default';

  String _scopeUserId(String scope) =>
      Uri.decodeComponent(scope.substring(_userPrefix.length));

  String get _currentScope {
    final id = _userId();
    return id == null ? _guestScope : '$_userPrefix${Uri.encodeComponent(id)}';
  }

  Future<void> start() {
    if (_disposed) return Future<void>.value();
    if (_started) return _startFuture ?? Future<void>.value();
    _started = true;
    _authChanges?.addListener(_onAuthChanged);
    return _startFuture = reload();
  }

  void _onAuthChanged() {
    if (_scope != _currentScope) unawaited(reload());
  }

  void _syncScope() {
    if (_scope == _currentScope) return;
    _scope = _currentScope;
    _generation++;
    _addresses = const [];
    _selectedId = null;
    _error = null;
    _loaded = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _matches(String scope, int generation) =>
      !_disposed &&
      _scope == scope &&
      _currentScope == scope &&
      _generation == generation;

  void _requireScope(String scope, int generation) {
    if (!_matches(scope, generation)) {
      throw const DeliveryAddressException('delivery_session_changed');
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    // فشل عملية لا يمنع المحاولات اللاحقة، ويصل الخطأ لمستدعي تلك العملية.
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> reload() {
    if (_disposed) return Future<void>.value();
    _syncScope();
    final scope = _scope!;
    final generation = _generation;
    _loading = true;
    _notify();
    return _enqueue(() async {
      if (!_matches(scope, generation)) return;
      try {
        if (scope != _guestScope) {
          final rows = await _client()
              .from('delivery_addresses')
              .select(_columns)
              .eq('user_id', _scopeUserId(scope))
              .order('created_at')
              .order('id');
          if (_matches(scope, generation)) _applyCloud(rows, scope);
          return;
        }
        final preferences = await _preferences();
        await preferences.reload();
        if (!_matches(scope, generation)) return;
        final raw = preferences.getString(scope);
        final List<DeliveryAddress> loaded = [];
        String? selectedId;
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is! Map ||
              decoded['version'] != 1 ||
              decoded['addresses'] is! List) {
            throw const FormatException();
          }
          final entries = decoded['addresses'] as List;
          if (entries.length > maxAddresses) throw const FormatException();
          final ids = <String>{};
          for (final entry in entries) {
            if (entry is! Map) throw const FormatException();
            final address = DeliveryAddress.fromJson(
              Map<String, dynamic>.from(entry),
            );
            if (!ids.add(address.id)) throw const FormatException();
            loaded.add(address);
          }
          final storedSelection = decoded['selectedId'];
          if (storedSelection != null && storedSelection is! String) {
            throw const FormatException();
          }
          selectedId = ids.contains(storedSelection)
              ? storedSelection as String?
              : (loaded.isEmpty ? null : loaded.first.id);
        }
        _addresses = loaded;
        _selectedId = selectedId;
        _loaded = true;
        _error = null;
      } catch (_) {
        if (!_matches(scope, generation)) return;
        _error = 'delivery_load_failed';
      } finally {
        if (_matches(scope, generation)) {
          _loading = false;
          _notify();
        }
      }
    });
  }

  Future<void> _mutate(
    Future<void> Function(String scope, int generation) action,
  ) {
    if (!_started) unawaited(start());
    if (_scope != _currentScope) unawaited(reload());
    final scope = _scope!;
    final generation = _generation;
    return _enqueue(() async {
      _requireScope(scope, generation);
      if (!_loaded || _error == 'delivery_load_failed') {
        throw const DeliveryAddressException('delivery_load_failed');
      }
      await action(scope, generation);
    });
  }

  Future<void> save(DeliveryAddress address) =>
      _mutate((scope, generation) async {
        if (scope != _guestScope) {
          await _cloudMutation('save_delivery_address', scope, generation, {
            'p_address': {
              'id': address.id,
              'label': address.label,
              'address_line': address.addressLine,
              'latitude': address.latitude,
              'longitude': address.longitude,
              'building': address.building,
              'floor': address.floor,
              'apartment': address.apartment,
              'notes': address.notes,
            },
          });
          return;
        }
        final next = List<DeliveryAddress>.of(_addresses);
        final index = next.indexWhere((item) => item.id == address.id);
        if (index < 0) {
          if (next.length >= maxAddresses) {
            throw const DeliveryAddressException('delivery_address_limit');
          }
          next.add(address);
        } else {
          next[index] = address;
        }
        await _persist(scope, generation, next, address.id);
      });

  Future<void> select(String id) => _mutate((scope, generation) async {
    if (scope != _guestScope) {
      await _cloudMutation('select_delivery_address', scope, generation, {
        'p_id': id,
      });
      return;
    }
    if (!_addresses.any((address) => address.id == id)) {
      throw const DeliveryAddressException('delivery_address_missing');
    }
    if (_selectedId == id) return;
    await _persist(scope, generation, _addresses, id);
  });

  Future<void> remove(String id) => _mutate((scope, generation) async {
    if (scope != _guestScope) {
      await _cloudMutation('delete_delivery_address', scope, generation, {
        'p_id': id,
      });
      return;
    }
    if (!_addresses.any((address) => address.id == id)) {
      throw const DeliveryAddressException('delivery_address_missing');
    }
    final next = _addresses.where((address) => address.id != id).toList();
    final selectedId = _selectedId == id
        ? (next.isEmpty ? null : next.first.id)
        : _selectedId;
    await _persist(scope, generation, next, selectedId);
  });

  void _applyCloud(List<dynamic> rows, String scope) {
    final loaded = <DeliveryAddress>[];
    final ids = <String>{};
    String? selectedId;
    for (final row in rows) {
      if (row is! Map || row['user_id'] != _scopeUserId(scope)) {
        throw const FormatException();
      }
      final address = DeliveryAddress.fromJson({
        ...Map<String, dynamic>.from(row),
        'addressLine': row['address_line'],
      });
      if (!ids.add(address.id)) throw const FormatException();
      if (row['is_default'] == true) {
        if (selectedId != null) throw const FormatException();
        selectedId = address.id;
      }
      loaded.add(address);
    }
    if (loaded.length > maxAddresses ||
        (loaded.isNotEmpty && selectedId == null)) {
      throw const FormatException();
    }
    _addresses = loaded;
    _selectedId = selectedId;
    _loaded = true;
    _error = null;
  }

  Future<void> _cloudMutation(
    String function,
    String scope,
    int generation,
    Map<String, dynamic> params,
  ) async {
    _requireScope(scope, generation);
    try {
      final rows = await _client().rpc(
        function,
        params: {...params, 'p_expected_user_id': _scopeUserId(scope)},
      );
      _requireScope(scope, generation);
      if (rows is! List) throw const FormatException();
      _applyCloud(rows, scope);
      _notify();
    } catch (error) {
      _requireScope(scope, generation);
      const allowedCodes = {
        'delivery_address_limit',
        'delivery_address_missing',
        'delivery_session_changed',
        'delivery_invalid_address',
        'delivery_invalid_location',
      };
      final code =
          error is PostgrestException && allowedCodes.contains(error.message)
          ? error.message
          : 'delivery_save_failed';
      _error = code;
      _notify();
      throw DeliveryAddressException(code);
    }
  }

  Future<void> _persist(
    String scope,
    int generation,
    List<DeliveryAddress> next,
    String? selectedId,
  ) async {
    final encoded = jsonEncode({
      'version': 1,
      'addresses': next.map((address) => address.toJson()).toList(),
      'selectedId': selectedId,
    });
    final preferences = await _preferences();
    _requireScope(scope, generation);
    try {
      final success =
          await (_writeString?.call(preferences, scope, encoded) ??
              preferences.setString(scope, encoded));
      if (!success) {
        throw const DeliveryAddressException('delivery_save_failed');
      }
    } catch (_) {
      // SharedPreferences يحدّث ذاكرته قبل إتمام الكتابة؛ نعيد قراءتها عند الفشل.
      try {
        await preferences.reload();
      } catch (_) {}
      if (_matches(scope, generation)) {
        _error = 'delivery_save_failed';
        _notify();
      }
      throw const DeliveryAddressException('delivery_save_failed');
    }
    _requireScope(scope, generation);
    _addresses = List<DeliveryAddress>.of(next);
    _selectedId = selectedId;
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    if (_started) _authChanges?.removeListener(_onAuthChanged);
    super.dispose();
  }
}
