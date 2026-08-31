// ============================================================
//  الدخول والتسجيل — مقابل app-login.html و app-register.html
//
//  صفحة واحدة بتبويبين، ونوع الحساب يأتي من بوابة نوع الحساب
//  قبلها. حقول المصنع الإضافية تظهر فقط لنوع factory.
//
//  مهم: عند تفعيل تأكيد البريد لا تُعاد جلسة بعد إنشاء الحساب،
//  فيجب ألّا نكتب شيئاً في profiles أو factories من هنا —
//  مُشغّل handle_new_user في الخادم أنشأ الصفوف، و RLS سترفض
//  أي كتابة لأن auth.uid() لا تزال فارغة.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';
import '../widgets/wordmark.dart';
import 'shell.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.accountType,
    this.startOnRegister = false,
  });

  /// individual أو factory — يأتي من البوابة السابقة.
  final String accountType;
  final bool startOnRegister;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool get isFactory => widget.accountType == 'factory';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.startOnRegister ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(
        title: const Wordmark(fontSize: 12, width: 120),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: SFColors.green,
          indicatorWeight: 3,
          labelColor: SFColors.white,
          unselectedLabelColor: SFColors.muted,
          labelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          tabs: [
            Tab(text: i18n.t('splash_login_btn')),
            Tab(text: i18n.t('splash_signup_btn')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _LoginForm(accountType: widget.accountType),
          _RegisterForm(accountType: widget.accountType, isFactory: isFactory),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  تبويب الدخول
// ------------------------------------------------------------

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.accountType});

  final String accountType;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.instance.signIn(_email.text, _password.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = arabicAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'اكتب بريدك الإلكتروني أولاً.');
      return;
    }
    try {
      await AuthService.instance.resetPassword(email);
      if (!mounted) return;
      // رسالة واحدة سواء وُجد الحساب أم لا — حتى لا يتمكّن أحد
      // من معرفة البُرد المسجّلة عندنا.
      showSFMessage(context,
          'إن كان هذا البريد مسجّلاً فستصلك رسالة لإعادة تعيين كلمة المرور.');
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            if (_error != null) _ErrorBox(text: _error!),
            _Field(
              label: i18n.t('field_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'صيغة البريد الإلكتروني غير صحيحة.'
                  : null,
            ),
            _Field(
              label: i18n.t('field_password'),
              controller: _password,
              obscure: _hidePassword,
              validator: (v) => (v == null || v.length < 6)
                  ? 'كلمة المرور قصيرة — 6 أحرف على الأقل.'
                  : null,
              suffix: IconButton(
                icon: Icon(
                  _hidePassword ? Icons.visibility_off : Icons.visibility,
                  color: SFColors.muted,
                ),
                onPressed: () =>
                    setState(() => _hidePassword = !_hidePassword),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _forgotPassword,
                child: Text(
                  i18n.t('forgot_password'),
                  style: const TextStyle(color: SFColors.midGreen),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: SFColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(i18n.t('splash_login_btn')),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
//  تبويب التسجيل
// ------------------------------------------------------------

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.accountType, required this.isFactory});

  final String accountType;
  final bool isFactory;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _cr = TextEditingController();
  final _industrialLicense = TextEditingController();

  // العنوان الوطني — نفس الأعمدة المفكوكة في القاعدة.
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _shortAddress = TextEditingController();
  final _building = TextEditingController();
  final _secondary = TextEditingController();
  final _postal = TextEditingController();
  final _street = TextEditingController();

  String _gender = '';
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _success;

  @override
  void dispose() {
    for (final c in [
      _name, _email, _phone, _password, _cr, _industrialLicense,
      _city, _district, _shortAddress, _building, _secondary,
      _postal, _street,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    try {
      final res = await AuthService.instance.signUp(
        email: _email.text,
        password: _password.text,
        data: {
          'account_type': widget.accountType,
          'full_name': _name.text.trim(),
          'gender': _gender,
          'phone': _phone.text.trim(),
          'commercial_register': _cr.text.trim(),
          'industrial_license': _industrialLicense.text.trim(),
          'address_city': _city.text.trim(),
          'address_district': _district.text.trim(),
          'address_short': _shortAddress.text.trim(),
          'address_building': _building.text.trim(),
          'address_secondary': _secondary.text.trim(),
          'address_postal': _postal.text.trim(),
          'address_street': _street.text.trim(),
        },
      );

      if (!mounted) return;

      if (res.user == null) {
        setState(() => _error = 'تعذّر إكمال إنشاء الحساب. حاول مرة أخرى.');
        return;
      }

      // لا جلسة ⇒ تأكيد البريد مفعّل. لا نكتب شيئاً في القاعدة.
      if (res.session == null) {
        setState(() => _success = context.t('signup_email_confirmation'));
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = arabicAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            if (_error != null) _ErrorBox(text: _error!),
            if (_success != null) _SuccessBox(text: _success!),

            _Field(
              label: i18n.t('field_name'),
              controller: _name,
              validator: _required,
            ),
            _Field(
              label: i18n.t('field_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'صيغة البريد الإلكتروني غير صحيحة.'
                  : null,
            ),
            _Field(
              label: i18n.t('field_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: _required,
            ),
            _Field(
              label: i18n.t('field_password'),
              controller: _password,
              obscure: _hidePassword,
              validator: (v) => (v == null || v.length < 6)
                  ? 'كلمة المرور قصيرة — 6 أحرف على الأقل.'
                  : null,
              suffix: IconButton(
                icon: Icon(
                  _hidePassword ? Icons.visibility_off : Icons.visibility,
                  color: SFColors.muted,
                ),
                onPressed: () =>
                    setState(() => _hidePassword = !_hidePassword),
              ),
            ),

            // الجنس — للأفراد فقط، كما في النسخة القديمة.
            if (!widget.isFactory) ...[
              const SizedBox(height: 4),
              Text(
                i18n.t('field_gender'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              RadioGroup<String>(
                groupValue: _gender,
                onChanged: (v) => setState(() => _gender = v ?? ''),
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'male',
                        title: Text(i18n.t('gender_male')),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: SFColors.midGreen,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'female',
                        title: Text(i18n.t('gender_female')),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: SFColors.midGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // حقول المصنع.
            if (widget.isFactory) ...[
              _Field(
                label: i18n.t('field_cr'),
                controller: _cr,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _required,
              ),
              _Field(
                label: i18n.t('field_industrial_license'),
                controller: _industrialLicense,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],

            const SizedBox(height: 6),
            Text(
              i18n.t('addr_modal_title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _Field(label: i18n.t('addr_city'), controller: _city),
            _Field(label: i18n.t('addr_district'), controller: _district),
            _Field(
              label: i18n.t('addr_short'),
              controller: _shortAddress,
              maxLength: 8,
            ),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: i18n.t('addr_building'),
                    controller: _building,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    label: i18n.t('addr_secondary'),
                    controller: _secondary,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            _Field(
              label: i18n.t('addr_postal'),
              controller: _postal,
              keyboardType: TextInputType.number,
              maxLength: 5,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            _Field(label: i18n.t('addr_street'), controller: _street),

            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _busy || _success != null ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: SFColors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(_success != null
                      ? i18n.t('signup_confirmation_sent')
                      : i18n.t('splash_signup_btn')),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب.' : null;
}

// ------------------------------------------------------------
//  عناصر مساعدة
// ------------------------------------------------------------

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscure = false,
    this.validator,
    this.suffix,
    this.maxLength,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscure,
            validator: validator,
            maxLength: maxLength,
            inputFormatters: inputFormatters,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              suffixIcon: suffix,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SFColors.dangerBg,
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        border: Border.all(color: SFColors.danger.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: SFColors.danger, fontSize: 14),
      ),
    );
  }
}

class _SuccessBox extends StatelessWidget {
  const _SuccessBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3EE),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
        border: Border.all(color: SFColors.green),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: SFColors.midGreen,
          fontSize: 14,
          height: 1.7,
        ),
      ),
    );
  }
}

/// ترجمة رسائل Supabase إلى العربية — نفس الرسائل في نسخة الويب.
String arabicAuthError(Object e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('already registered') ||
      msg.contains('user already')) {
    return 'هذا البريد مسجّل مسبقاً. جرّب تسجيل الدخول.';
  }
  if (msg.contains('invalid login')) {
    return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
  }
  if (msg.contains('email not confirmed')) {
    return 'لم يتم تأكيد البريد بعد. افتح الرسالة المرسلة إليك.';
  }
  if (msg.contains('password') && msg.contains('6')) {
    return 'كلمة المرور قصيرة — 6 أحرف على الأقل.';
  }
  if (msg.contains('invalid') && msg.contains('email')) {
    return 'صيغة البريد الإلكتروني غير صحيحة.';
  }
  if (msg.contains('failed host lookup') ||
      msg.contains('network') ||
      msg.contains('socket')) {
    return 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت وحاول مجدداً.';
  }
  return 'حدث خطأ: ${e.toString().replaceFirst('Exception: ', '')}';
}
