-- ============================================================
--  إحصائية الصفحة الرئيسية — 2026-09-04
--
--  بطلب المالك: أرقام حقيقية بجانب الخريطة — عدد المصانع،
--  والكميات المباعة، والإيرادات — "ومربوطة وماتكون شكل فقط".
--
--  لماذا دالة على الخادم ولا يكفي استعلام من الصفحة:
--  سياسة orders_select_party تحصر الطلبات في أطرافها (المشتري
--  وصاحب المصنع). فالزائر يقرأ صفراً دائماً — وهذا صحيح ولا
--  يجوز كسره لعرض إحصاءة.
--
--  الحل دالة security definer تُرجع المجاميع وحدها: أرقاماً
--  مجمّعة لا صفوفاً. فلا تكشف من اشترى ولا بكم ولا من أي مصنع،
--  ويبقى حاجز RLS على الجداول نفسه كما هو.
--
--  الطلبات الملغاة والفاشلة مستثناة: عدّها إيراداً يضخّم الرقم
--  بما لم يُبَع فعلاً.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

create or replace function public.get_public_stats()
returns table (
  factories_count bigint,
  products_count  bigint,
  units_sold      numeric,
  revenue         numeric
)
language sql
security definer
set search_path = public
stable
as $fn$
  select
    (select count(*) from public.factories where status = 'approved'),
    (select count(*) from public.products p
       join public.factories f on f.id = p.factory_id
      where f.status = 'approved'),
    coalesce((
      select sum(oi.quantity)
        from public.order_items oi
        join public.orders o on o.id = oi.order_id
       where o.status not in ('cancelled', 'payment_failed')
    ), 0),
    coalesce((
      select sum(o.total)
        from public.orders o
       where o.status not in ('cancelled', 'payment_failed')
    ), 0);
$fn$;

-- الدالة عامة: الصفحة الرئيسية تفتح للزائر بلا حساب.
-- وهي تُرجع مجاميع لا صفوفاً، فلا تسرّب بيانات أحد.
revoke all on function public.get_public_stats() from public;
grant execute on function public.get_public_stats() to anon, authenticated;


-- ============================================================
--  تحقّق: يجب أن يظهر صفّ واحد بالأرقام الأربعة
-- ============================================================
select * from public.get_public_stats();
