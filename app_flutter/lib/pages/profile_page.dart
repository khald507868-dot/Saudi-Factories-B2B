// ============================================================
//  الملف الشخصي — مقابل app-profile.html
//
//  الحفظ عند الضغط لا عند الكتابة، لأن الحقول تُرسل معاً.
//  الصورة تُرفع إلى التخزين ويُحفظ رابطها — لا base64.
//
//  ملاحظة: account_type لا يظهر للتعديل. حارس القاعدة يُعيده
//  إلى قيمته مهما أُرسل، فإظهاره حقلاً قابلاً للتعديل يوهم
//  المستخدم بتغيير لا يحدث.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../core/supabase_config.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/upload_service.dart';
import '../widgets/common.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _countryCode = TextEditingController();
  String _gender = '';
  DateTime? _birthdate;

  String _image = '';
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final p = AuthService.instance.profile;
    _name.text = p?.fullName ?? '';
    _phone.text = p?.phone ?? '';
    _email.text = AuthService.instance.user?.email ?? p?.email ?? '';
    _countryCode.text = p?.countryCode ?? '+966';
    _gender = p?.gender ?? '';
    _birthdate = p?.birthdate;
    _image = p?.companyImage ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _countryCode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _uploading = true);
    try {
      final url = await SFUpload.pickAndUploadImage(
        bucket: SFBuckets.factoryMedia,
        folder: 'profile',
        maxSize: 640,
      );
      if (url == null) return;
      if (!mounted) return;
      setState(() => _image = url);
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final uid = AuthService.instance.user?.id;
    if (uid == null) return;
    if (_name.text.trim().isEmpty ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) ||
        !RegExp(r'^\+\d{1,4}$').hasMatch(_countryCode.text.trim())) {
      showSFError(context, Exception(context.t('profile_invalid_fields')));
      return;
    }

    setState(() => _saving = true);
    try {
      await sb
          .from('profiles')
          .update({
            'full_name': _name.text.trim(),
            'phone': _phone.text.trim(),
            'company_image': _image,
            'gender': _gender,
            'country_code': _countryCode.text.trim(),
            'birthdate': _birthdate == null
                ? null
                : '${_birthdate!.year.toString().padLeft(4, '0')}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
          })
          .eq('id', uid);

      final changedEmail =
          _email.text.trim() != AuthService.instance.user?.email;
      if (changedEmail) {
        await sb.auth.updateUser(UserAttributes(email: _email.text.trim()));
      }

      await AuthService.instance.refreshProfile();
      if (!mounted) return;
      showSFMessage(
        context,
        context.t(changedEmail ? 'profile_email_confirmation' : 'saved_msg'),
      );
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final profile = AuthService.instance.profile;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(title: Text(i18n.t('row_profile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SFColors.white,
              border: Border.all(color: SFColors.border),
              borderRadius: BorderRadius.circular(SFMetrics.radius),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    SFImage(
                      url: _image,
                      width: 72,
                      height: 72,
                      radius: 999,
                      placeholderIcon: Icons.person_outline,
                    ),
                    PositionedDirectional(
                      bottom: 0,
                      end: 0,
                      child: InkWell(
                        onTap: _uploading ? null : _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: SFColors.midGreen,
                            shape: BoxShape.circle,
                          ),
                          child: _uploading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    color: SFColors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_outlined,
                                  size: 15,
                                  color: SFColors.white,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.fullName ?? i18n.t('row_profile'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i18n.t(
                          profile?.isFactory == true
                              ? 'dash_account_factory'
                              : 'dash_account_individual',
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: SFColors.muted2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _Labelled(
            label: i18n.t('field_name'),
            child: TextField(
              controller: _name,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          _Labelled(
            label: i18n.t('field_phone'),
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          _Labelled(
            label: i18n.t('profile_country_code'),
            child: TextField(
              controller: _countryCode,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
            ),
          ),
          if (profile?.isFactory != true) ...[
            _Labelled(
              label: i18n.t('field_gender'),
              child: DropdownButtonFormField<String>(
                initialValue: ['male', 'female'].contains(_gender)
                    ? _gender
                    : null,
                items: [
                  for (final gender in ['male', 'female'])
                    DropdownMenuItem(
                      value: gender,
                      child: Text(i18n.t('gender_$gender')),
                    ),
                ],
                onChanged: (value) => setState(() => _gender = value ?? ''),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
              tileColor: SFColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SFMetrics.radius),
                side: const BorderSide(color: SFColors.border),
              ),
              title: Text(i18n.t('field_birthdate')),
              subtitle: Text(
                _birthdate == null
                    ? '—'
                    : '${_birthdate!.day}/${_birthdate!.month}/${_birthdate!.year}',
              ),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _birthdate ?? DateTime(2000),
                );
                if (date != null && mounted) setState(() => _birthdate = date);
              },
            ),
            const SizedBox(height: 16),
          ],
          // تغيير البريد يمرّ عبر تأكيد Supabase؛ نوع الحساب ثابت.
          _Labelled(
            label: i18n.t('field_email'),
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
            ),
          ),
          _Labelled(
            label: i18n.t('dash_account_factory'),
            child: _ReadOnly(
              text: i18n.t(
                profile?.isFactory == true
                    ? 'dash_account_factory'
                    : 'dash_account_individual',
              ),
            ),
          ),

          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: SFColors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(i18n.t('btn_update')),
          ),
        ],
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: SFColors.surfaceAlt,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Text(
        text.isEmpty ? '—' : text,
        style: const TextStyle(fontSize: 14, color: SFColors.muted2),
      ),
    );
  }
}
