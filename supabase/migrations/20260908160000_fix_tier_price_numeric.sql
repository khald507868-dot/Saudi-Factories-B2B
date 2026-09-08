-- ============================================================
-- إصلاح: الشراء يفشل بـ tier_unit_price(bigint, numeric)
-- ------------------------------------------------------------
-- الدالّة معرّفة بـ (bigint, integer)، وcart_items.quantity
-- عمودها numeric(12,3) — وبوستجرس لا يحوّل numeric إلى
-- integer ضمنيّاً، فيبحث عن توقيع (bigint, numeric) ولا
-- يجده ويسقط الاستعلام كلّه.
--
-- والأثر أنّ create_order_from_cart تفشل لكلّ طلب: زرّ
-- الشراء لا يعمل لأيّ مشترٍ. ولم يظهر قبلُ لأنّ الشرائح
-- أُضيفت بعد آخر طلب حقيقي.
--
-- الحلّ توقيع numeric يستقبل ما يأتي من العمود، ويقصّ
-- الكسر بـfloor: من طلب 2.5 قطعة يقع في شريحة القطعتين لا
-- الثلاث — والتقريب لأعلى يعطيه سعراً أرخص لم يستحقّه.
--
-- ونسخة integer تبقى: تنادى من مواضع تمرّر عدداً صحيحاً،
-- وحذفها يكسرها بلا داعٍ.
--
-- يُطبَّق مرّة واحدة:
-- Supabase → SQL Editor → New query → لصق → Run
-- ============================================================

create or replace function public.tier_unit_price(
  p_product_id bigint,
  p_quantity   numeric
)
returns numeric
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    (select (t->>'price')::numeric
       from public.products p, lateral jsonb_array_elements(p.tiers) as t
      where p.id = p_product_id
        and floor(p_quantity) >= coalesce((t->>'min')::integer, 1)
        and ((t->>'max') is null
             or floor(p_quantity) <= (t->>'max')::integer)
      order by coalesce((t->>'min')::integer, 1) desc
      limit 1),
    (select price from public.products where id = p_product_id));
$fn$;

revoke all on function public.tier_unit_price(bigint, numeric) from public, anon;
grant execute on function public.tier_unit_price(bigint, numeric) to authenticated, anon;

-- تحقّق: يجب أن يظهر التوقيعان معاً --------------------------
select p.oid::regprocedure::text as signature
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'tier_unit_price'
 order by 1;
