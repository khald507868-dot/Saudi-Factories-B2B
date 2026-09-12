-- الخطوة الثانية: تضييق EXECUTE بناءً على تصدير دوال الإنتاج وسياساته.
-- لا نحذف دوال أو بيانات، ولا نعطل المشغلات أو نغيّر سياسات RLS.
begin;

-- نرفض التغيير إذا اختلفت تبعيات الإنتاج عن النسخة التي راجعناها.
do $check$
begin
  if exists (
    select 1 from pg_policies
    where schemaname in ('public', 'storage')
      and concat(qual, ' ', with_check)
        ~ '(has_purchased_product|can_review_product|get_message_products)[[:space:]]*\('
  ) then
    raise exception 'Review policy dependencies before restricting these functions';
  end if;
  if not exists (
    select 1 from pg_proc reviews
    join pg_proc purchase on purchase.proowner = reviews.proowner
    where reviews.oid = to_regprocedure('public.get_product_reviews(bigint,integer,integer)')
      and purchase.oid = to_regprocedure('public.has_purchased_product(bigint,uuid)')
      and reviews.prosecdef
  ) then
    raise exception 'Verified-review function must execute as the purchase-helper owner';
  end if;
end;
$check$;

-- هذه الدالة تقرأ الطلبات بمعرّف مستخدم يُمرَّر إليها.
-- يستدعيها get_product_reviews داخلياً بصلاحيات مالك الدالة لإظهار شارة المشتري.
-- لا يحتاج الزائر أو الحساب العادي إلى استدعائها مباشرةً عن أي مستخدم.
revoke execute on function public.has_purchased_product(bigint, uuid)
  from public, anon, authenticated;

-- هاتان العمليتان تخصان حساباً مسجّلاً؛ التحقق من الهوية داخل الدوال باقٍ.
revoke execute on function public.can_review_product(bigint) from public, anon;
grant execute on function public.can_review_product(bigint) to authenticated;
revoke execute on function public.get_message_products(bigint) from public, anon;
grant execute on function public.get_message_products(bigint) to authenticated;

-- PostgreSQL يشغّل الدوال المربوطة بالمشغلات داخلياً عند تعديل الصفوف.
-- العملاء لا يحتاجون EXECUTE مباشرًا على دوال trigger / event_trigger.
do $triggers$
declare
  target regprocedure;
begin
  for target in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.prosecdef
      and p.prorettype in ('pg_catalog.trigger'::regtype, 'pg_catalog.event_trigger'::regtype)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', target);
  end loop;
end;
$triggers$;

notify pgrst, 'reload schema';
commit;
