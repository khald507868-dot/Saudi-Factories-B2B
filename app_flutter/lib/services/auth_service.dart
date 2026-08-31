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

import 'package:flutter/material.dart';
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
  });

  final String id;
  final String? accountType;
  final String? fullName;
  final String? phone;
  final String? email;
  final bool isAdmin;
  final String? companyImage;

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
    );
  }
}

class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  User? _user;
  SFProfile? _profile;
  bool _ready = false;

  User? get user => _user;
  SFProfile? get profile => _profile;
  bool get isSignedIn => _user != null;

  /// اكتمل الفحص الأول للجلسة — مقابل SF_AUTH_READY.
  bool get ready => _ready;

  /// يُستدعى مرة واحدة عند الإقلاع، ثم يتابع تغيّرات الجلسة.
  Future<void> start() async {
    _user = sb.auth.currentUser;
    if (_user != null) {
      await _loadProfile();
    }
    _ready = true;
    notifyListeners();

    sb.auth.onAuthStateChange.listen((data) async {
      final next = data.session?.user;
      final changed = next?.id != _user?.id;
      _user = next;
      if (next == null) {
        _profile = null;
      } else if (changed) {
        await _loadProfile();
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile() async {
    final id = _user?.id;
    if (id == null) return;
    try {
      final row = await sb
          .from('profiles')
          .select(
              'account_type, full_name, phone, email, is_admin, company_image')
          .eq('id', id)
          .maybeSingle();
      if (row != null) {
        _profile = SFProfile.fromMap(id, row);
      }
    } catch (_) {
      // انقطاع الشبكة لا يُخرج المستخدم — الجلسة قد تكون سليمة.
    }
  }

  /// إعادة قراءة الملف الشخصي بعد تعديله.
  Future<void> refreshProfile() async {
    await _loadProfile();
    notifyListeners();
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await sb.auth.signInWithPassword(
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
    final res = await sb.auth.signUp(
      email: email.trim(),
      password: password,
      data: data,
    );
    _user = res.user;
    if (res.session != null && _user != null) await _loadProfile();
    notifyListeners();
    return res;
  }

  Future<void> resetPassword(String email) async {
    await sb.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() async {
    await sb.auth.signOut();
    _user = null;
    _profile = null;
    notifyListeners();
  }
}
