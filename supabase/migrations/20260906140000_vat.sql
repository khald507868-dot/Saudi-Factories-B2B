-- ============================================================
--  ضريبة القيمة المضافة 15% — 2026-09-06
--
--  بطلب المالك: تُحسب الضريبة على قيمة الطلب كاملة — قيمة
--  المنتجات والتوصيل ورسوم بوابة الدفع — ثم تُجمع على المبلغ
--  فيكون الناتج قيمة الطلب النهائية.
--
--  القيم بطلب المالك: التوصيل 30 ريالاً، ورسوم بوابة الدفع 1%
--  من قيمة المنتجات والتوصيل معاً.
--
--  وتُحفظ المبالغ مع كلّ طلب لا تُقرأ من ثوابت وقت العرض:
--  لو تغيّرت أجرة التوصيل غداً، بقيت فواتير الأمس صحيحة.
--
--  لماذا الحساب على الخادم:
--  المعادلة كلّها داخل create_order_from_cart، ولا تقبل الدالة
--  أيّ مبلغ من العميل — وهذا ما يجعل التلاعب بالسعر مستحيلاً
--  بنيةً لا بسياسة قد تُنسى. الضريبة تتبع القاعدة نفسها.
--
--  التقريب: round(...,2) على مبلغ الضريبة وحده، ثم يُجمع.
--  وجمع مبالغ غير مقرّبة ثم تقريب المجموع يُنتج فرق هللة عن
--  الفاتورة المطبوعة، وهذا ما يُراجَع عليه محاسبياً.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

-- ------------------------------------------------------------
--  1) أعمدة المبالغ
-- ------------------------------------------------------------
alter table public.orders
  add column if not exists shipping numeric(14, 2) not null default 0
    check (shipping >= 0);

alter table public.orders
  add column if not exists payment_fee numeric(14, 2) not null default 0
    check (payment_fee >= 0);

alter table public.orders
  add column if not exists vat_rate numeric(5, 4) not null default 0.15
    check (vat_rate >= 0 and vat_rate <= 1);

-- النسبة تُخزَّن مع كل طلب لا تُقرأ من ثابت في الكود: لو تغيّرت
-- الضريبة نظاماً، بقيت الطلبات القديمة محسوبة بنسبتها وقت البيع،
-- وهذا شرط سلامة الفواتير القديمة.
alter table public.orders
  add column if not exists vat_amount numeric(14, 2) not null default 0
    check (vat_amount >= 0);


-- ------------------------------------------------------------
--  2) إنشاء الطلب: المعادلة الكاملة
-- ------------------------------------------------------------
create or replace function public.create_order_from_cart(
  p_factory_id bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $fn$
declare
  cart_row public.carts%rowtype;
  result_row public.orders%rowtype;
  subtotal_value numeric(14,2);
  shipping_value numeric(14,2) := 30;
  fee_rate_value numeric(5,4) := 0.01;
  fee_value numeric(14,2);
  taxable_value numeric(14,2);
  vat_rate_value numeric(5,4) := 0.15;
  vat_value numeric(14,2);
  total_value numeric(14,2);
  item_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_factory_id is null then raise exception 'Factory is required' using errcode = '22023'; end if;

  select * into cart_row from public.carts where owner_id = auth.uid() for update;
  if not found then raise exception 'Cart is empty' using errcode = '22023'; end if;

  select count(*), coalesce(sum(
    ci.quantity * coalesce(cp.price, p.price)
  ), 0)
    into item_count, subtotal_value
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id and p.factory_id = p_factory_id;

  if item_count = 0 then raise exception 'Cart has no products for this factory' using errcode = '22023'; end if;
  if exists (
    select 1 from public.cart_items ci join public.products p on p.id = ci.product_id
     where ci.cart_id = cart_row.id and p.factory_id <> p_factory_id
  ) then
    raise exception 'Create one order per factory' using errcode = '22023';
  end if;

  -- رسوم البوابة نسبة ممّا يمرّ عبرها — المنتجات والتوصيل معاً
  -- لا قيمة البضاعة وحدها.
  fee_value := round((subtotal_value + shipping_value) * fee_rate_value, 2);

  taxable_value := subtotal_value + shipping_value + fee_value;
  vat_value := round(taxable_value * vat_rate_value, 2);
  total_value := taxable_value + vat_value;

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, shipping, payment_fee,
    vat_rate, vat_amount, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_payment', subtotal_value,
    shipping_value, fee_value, vat_rate_value, vat_value, total_value,
    p_idempotency_key
  ) on conflict (buyer_id, idempotency_key) do update
    set updated_at = excluded.updated_at
  returning * into result_row;

  insert into public.order_items (
    order_id, product_id, product_name, unit_price, quantity, line_total
  )
  select result_row.id, p.id, p.name,
         coalesce(cp.price, p.price), ci.quantity,
         coalesce(cp.price, p.price) * ci.quantity
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id;

  delete from public.cart_items where cart_id = cart_row.id;
  return result_row;
end;
$fn$;

revoke all on function public.create_order_from_cart(bigint, uuid)
  from public, anon;
grant execute on function public.create_order_from_cart(bigint, uuid)
  to authenticated;


-- ------------------------------------------------------------
--  3) الطلبات القائمة قبل هذه الهجرة
--
--  أُنشئت بلا ضريبة، فقيمتها الحالية هي وعاء الضريبة نفسه.
--  تُحدَّث مرّة واحدة فقط (vat_amount = 0) فإعادة تشغيل الملف
--  لا تضاعف الضريبة عليها.
-- ------------------------------------------------------------
update public.orders
   set shipping = 30,
       payment_fee = round((subtotal + 30) * 0.01, 2),
       vat_amount = round(
         (subtotal + 30 + round((subtotal + 30) * 0.01, 2)) * vat_rate, 2),
       total = subtotal + 30 + round((subtotal + 30) * 0.01, 2)
             + round(
                 (subtotal + 30 + round((subtotal + 30) * 0.01, 2)) * vat_rate, 2),
       updated_at = now()
 where vat_amount = 0
   and status not in ('cancelled', 'payment_failed');


-- ============================================================
--  تحقّق: الأعمدة والمبالغ بعد التحديث
-- ============================================================
select id, subtotal, shipping, payment_fee, vat_rate, vat_amount, total
  from public.orders
 order by created_at desc
 limit 5;
