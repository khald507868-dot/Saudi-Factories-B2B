// ============================================================
//  حالة الجلسة والملف الشخصي — مقابل auth-guard.js
//
//  ملاحظة مهمة (منقولة من نسخة الويب): هذا حارس تجربة استخدام
//  لا حماية بيانات. الحماية الحقيقية في سياسات RLS داخل الخادم.
//
//  فرق عن الويب: لا يوجد "توجيه" هنا؛ التطبيق يعرض شاشة الدخول
//  أو المحتوى حسب الحالة، ولا حاجة لـ SF_PUBLIC_PAGE لأن كل
//  شاشة تقرّر بنفسها هل تتطلّب حساباً (عبر requireLogin).
// ============================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';

/// الملف الشخصي كما تقرأه نسخة الويب — نفس قائمة الأعمدة.
/// أي شاشة تحتاج عموداً إضافياً يجب أن تضيفه هنا أولاً،
/// وإلا لن يكون موجوداً في [AuthService.profile].
class SFProfile {
  const SFProfile({
    required this.id,
    this.accountType,
    this.fullName,
    this.phone,
    this.email,
    this.isAdmin = false,
    this.companyImage,
    this.gender = '',
    this.countryCode = '+966',
    this.countryFlag = '🇸🇦',
    this.birthdate,
  });

  final String id;
  final String? accountType;
  final String? fullName;
  final String? phone;
  final String? email;
  final bool isAdmin;
  final String? companyImage;
  final String gender;
  final String countryCode;
  final String countryFlag;
  final DateTime? birthdate;

  bool get isFactory => accountType == 'factory';

  factory SFProfile.fromMap(String id, Map<String, dynamic> m) {
    return SFProfile(
      id: id,
      accountType: m['account_type'] as String?,
      fullName: m['full_name'] as String?,
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      isAdmin: m['is_admin'] == true,
      companyImage: m['company_image'] as String?,
      gender: m['gender'] as String? ?? '',
      countryCode: m['country_code'] as String? ?? '+966',
      countryFlag: m['country_flag'] as String? ?? '🇸🇦',
      birthdate: DateTime.tryParse('${m['birthdate'] ?? ''}'),
    );
  }
}

class AuthService extends ChangeNotifier {
  AuthService._();

  @visibleForTesting
  AuthService.forTesting(this._client, [this._settingsClient]);

  static final AuthService instance = AuthService._();
  SupabaseClient? _client;
  http.Client? _settingsClient;
  SupabaseClient get _supabase => _client ?? sb;
  StreamSubscription<AuthState>? _subscription;

  User? _user;
  SFProfile? _profile;
  bool _ready = false;
  String _accessState = 'checking';
  String? rejectionReason;
  int _accessRequest = 0;
  String get accessState => _accessState;

  User? get user => _user;
  SFProfile? get profile => _profile;
  bool get isSignedIn => _user != null && _accessState == 'ready';

  /// اكتمل الفحص الأول للجلسة — مقابل SF_AUTH_READY.
  bool get ready => _ready;

  /// يُستدعى مرة واحدة عند الإقلاع، ثم يتابع تغيّرات الجلسة.
  Future<void> start() async {
    _user = _supabase.auth.currentUser;
    if (_user != null) {
      await _loadProfile();
    } else {
      _accessState = 'signed_out';
    }
    _ready = true;
    notifyListeners();

    await _subscription?.cancel();
    _subscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final next = data.session?.user;
      _user = next;
      if (next == null) {
        _accessRequest++;
        _accessState = 'signed_out';
        _profile = null;
        rejectionReason = null;
      } else {
        await _loadProfile();
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile({bool silent = false}) async {
    final id = _user?.id;
    if (id == null) return;
    final request = ++_accessRequest;
    // Never retain another session's privileges/details if this request fails.
    _profile = null;
    rejectionReason = null;
    if (!silent) {
      _accessState = 'checking';
      notifyListeners();
    }
    try {
      final verified = await _supabase.auth.getUser().timeout(
        const Duration(seconds: 15),
      );
      if (request != _accessRequest || _user?.id != id) return;
      if (verified.user == null || verified.user!.id != id) {
        throw const AuthException('Session unavailable');
      }
      _user = verified.user;
      if (verified.user!.emailConfirmedAt == null) {
        _accessState = 'email_required';
        return;
      }
      final row = await _supabase
          .from('profiles')
          .select(
            'account_type, full_name, phone, email, is_admin, company_image, gender, country_code, country_flag, birthdate',
          )
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
      if (request != _accessRequest || _user?.id != id) return;
      if (row != null) {
        if (row['account_type'] != 'individual' &&
            row['account_type'] != 'factory') {
          throw const AuthException('Invalid account type');
        }
        _profile = SFProfile.fromMap(id, row);
      } else {
        throw const AuthException('Profile unavailable');
      }
      rejectionReason = null;
      if (_profile!.isFactory && !_profile!.isAdmin) {
        final factory = await _supabase
            .from('factories')
            .select('status,rejection_reason')
            .eq('owner_id', id)
            .order('id')
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 15));
        if (request != _accessRequest || _user?.id != id) return;
        rejectionReason = factory?['rejection_reason'] as String?;
        _accessState = factory?['status'] == 'approved'
            ? 'ready'
            : factory?['status'] == 'rejected'
            ? 'rejected'
            : 'pending';
      } else {
        _accessState = 'ready';
      }
    } catch (_) {
      if (request == _accessRequest && _user?.id == id) _accessState = 'error';
    }
  }

  /// إعادة قراءة الملف الشخصي بعد تعديله.
  Future<void> refreshProfile({bool silent = false}) async {
    await _loadProfile(silent: silent);
    notifyListeners();
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _user = res.user;
    if (_user != null) await _loadProfile();
    notifyListeners();
    return res;
  }

  /// التسجيل — كل بيانات الملف الأولية تُرسل في user metadata،
  /// ومُشغّل handle_new_user في القاعدة هو من ينشئ صفّ profiles
  /// (وصفّ factories عند حساب المصنع بحالة pending).
  ///
  /// مع تفعيل تأكيد البريد لا تُعاد جلسة، فيجب ألّا تكتب الشاشة
  /// أي شيء في profiles/factories بعد هذا الاستدعاء — RLS سترفضه
  /// لأن auth.uid() لا تزال فارغة.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    final settings = await (_settingsClient?.get ?? http.get)(
      Uri.parse('$kSupabaseUrl/auth/v1/settings'),
      headers: {'apikey': kSupabaseKey},
    ).timeout(const Duration(seconds: 15));
    if (settings.statusCode != 200 ||
        (jsonDecode(settings.body) as Map)['mailer_autoconfirm'] != false) {
      throw const AuthException('Email verification is currently unavailable.');
    }
    await signOut(scope: SignOutScope.local);
    final res = await _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      data: data,
    );
    if (res.session != null) {
      await signOut(scope: SignOutScope.local);
      throw const AuthException('Email verification is currently unavailable.');
    }
    // With email confirmation enabled Supabase returns a User but no Session.
    // Such a user is not authenticated yet and must not pass client-side guards.
    _user = res.session?.user;
    _profile = null;
    _accessState = 'signed_out';
    if (_user != null) await _loadProfile();
    notifyListeners();
    return res;
  }

  Future<void> verifyEmail(String email, String token) async {
    final res = await _supabase.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
    if (res.session == null || res.user?.emailConfirmedAt == null) {
      throw const AuthException('Invalid verification');
    }
    _user = res.user;
    await _loadProfile();
    notifyListeners();
  }

  Future<void> resendCode(String email) =>
      _supabase.auth.resend(email: email.trim(), type: OtpType.signup);

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    await _supabase.auth.signOut(scope: scope);
    _user = null;
    _profile = null;
    _accessRequest++;
    _accessState = 'signed_out';
    rejectionReason = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _accessRequest++;
    _subscription?.cancel();
    super.dispose();
  }
}
