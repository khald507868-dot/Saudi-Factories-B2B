-- ============================================================
-- إصلاح التسجيل عند تفعيل تأكيد البريد الإلكتروني
--
-- المشكلة السابقة:
--   عند تفعيل Confirm email يعيد signUp مستخدمًا بلا جلسة.
--   لذلك كانت تحديثات profiles وfactories من المتصفح تُرفض بـ RLS.
--
-- الحل:
--   تمرّر صفحات التسجيل البيانات غير الحساسة في raw_user_meta_data،
--   وينشئ هذا المشغّل الملف والمصنع داخل الخادم لحظة إنشاء auth.users.
--   لا تُقرأ أي صلاحية إدارية أو حالة اعتماد من metadata.
--
-- طريقة التطبيق:
--   Supabase → SQL Editor → New query → الصق الملف كاملًا → Run
--
-- آمن للتكرار: يستبدل الدالة والمشغّل بالنسخة الحالية.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  meta      jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  acct_type text;
begin
  acct_type := coalesce(meta->>'account_type', 'individual');
  if acct_type not in ('individual', 'factory') then
    acct_type := 'individual';
  end if;

  insert into public.profiles (
    id,
    account_type,
    full_name,
    gender,
    country_flag,
    country_code,
    phone,
    email
  )
  values (
    new.id,
    acct_type,
    coalesce(meta->>'full_name', ''),
    coalesce(meta->>'gender', ''),
    coalesce(meta->>'country_flag', ''),
    coalesce(meta->>'country_code', ''),
    coalesce(meta->>'phone', ''),
    coalesce(new.email, '')
  )
  on conflict (id) do update set
    full_name    = excluded.full_name,
    gender       = excluded.gender,
    country_flag = excluded.country_flag,
    country_code = excluded.country_code,
    phone        = excluded.phone,
    email        = excluded.email;

  if acct_type = 'factory' then
    insert into public.factories (
      owner_id,
      name,
      status,
      commercial_register,
      industrial_license,
      address_city,
      address_district,
      address_short,
      address_building,
      address_secondary,
      address_postal,
      address_street
    )
    values (
      new.id,
      coalesce(meta->>'full_name', ''),
      'pending',
      coalesce(meta->>'commercial_register', ''),
      coalesce(meta->>'industrial_license', ''),
      coalesce(meta->>'address_city', ''),
      coalesce(meta->>'address_district', ''),
      coalesce(meta->>'address_short', ''),
      coalesce(meta->>'address_building', ''),
      coalesce(meta->>'address_secondary', ''),
      coalesce(meta->>'address_postal', ''),
      coalesce(meta->>'address_street', '')
    )
    on conflict (owner_id) do update set
      name                = excluded.name,
      commercial_register = excluded.commercial_register,
      industrial_license  = excluded.industrial_license,
      address_city        = excluded.address_city,
      address_district    = excluded.address_district,
      address_short       = excluded.address_short,
      address_building    = excluded.address_building,
      address_secondary   = excluded.address_secondary,
      address_postal      = excluded.address_postal,
      address_street      = excluded.address_street;
  end if;

  return new;
end;
$fn$;

comment on function public.handle_new_user()
  is 'ينشئ بيانات التسجيل الأولية خادميًا ويعمل مع تأكيد البريد دون جلسة متصفح';

-- يعاد إنشاء المشغّل لضمان ارتباطه بالنسخة المحدّثة من الدالة.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- تحقق اختياري بعد التشغيل:
--
-- select pg_get_functiondef('public.handle_new_user()'::regprocedure);
--
-- لا تنشئ مستخدم اختبار من SQL Editor؛ اختبر التسجيل من الواجهة
-- ببريد حقيقي جديد ثم تأكد من صفّي profiles وfactories.
-- ============================================================
