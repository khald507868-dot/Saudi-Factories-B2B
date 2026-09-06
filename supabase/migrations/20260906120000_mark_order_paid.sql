-- ============================================================
--  تأكيد استلام الدفع — 2026-09-06
--
--  بطلب المالك: زرّ يضغطه صاحب المصنع بعد استلام المال فعلاً،
--  فينتقل الطلب من "بانتظار الدفع" إلى "مدفوع" — بدل تعديل
--  الحالة يدوياً من لوحة Supabase.
--
--  لماذا دالة على الخادم ولا سياسة update:
--  لا توجد اليوم أيّ سياسة update على جدول orders، وهذا مقصود —
--  حالة الطلب مال، ولا يجوز أن يكتبها العميل مباشرة. وفتح سياسة
--  update يسمح للعميل بكتابة أيّ عمود: total، أو factory_id،
--  أو حالة يقفز بها إلى completed.
--
--  فالدالة تفعل شيئاً واحداً محدّداً: تنقل من pending أو
--  awaiting_payment إلى paid، لا غير. ولا تقبل من العميل إلا
--  رقم الطلب.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

create or replace function public.mark_order_paid(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_order public.orders;
begin
  -- صاحب المصنع وحده، أو المدير. المشتري لا يعلّم طلبه مدفوعاً
  -- بنفسه: المال يصل إلى المصنع، فهو الذي يشهد بوصوله.
  select o.* into v_order
    from public.orders o
    join public.factories f on f.id = o.factory_id
   where o.id = p_order_id
     and (f.owner_id = auth.uid() or public.is_admin())
   for update;

  if not found then
    raise exception 'Order access denied'
      using errcode = '42501';
  end if;

  -- الانتقال المسموح واحد فقط. ومنه يُمنع تعليم طلب ملغى
  -- أو فاشل الدفع مدفوعاً، ويُمنع إرجاع طلب شُحن أو اكتمل.
  if v_order.status not in ('pending', 'awaiting_payment') then
    raise exception 'Order is not awaiting payment (status: %)', v_order.status
      using errcode = '22023';
  end if;

  update public.orders
     set status = 'paid',
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$fn$;

-- المسجّلون فقط: الدالة تتحقّق من الملكية داخلياً، لكن سحب
-- الصلاحية عن anon يمنع الوصول إليها أصلاً — قفل الباب لا
-- الاكتفاء بحارس وراءه.
revoke all on function public.mark_order_paid(uuid) from public, anon;
grant execute on function public.mark_order_paid(uuid) to authenticated;


-- ============================================================
--  تحقّق: يجب أن يظهر سطر واحد باسم الدالة
-- ============================================================
select p.proname, pg_get_function_identity_arguments(p.oid) as args
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'mark_order_paid';
