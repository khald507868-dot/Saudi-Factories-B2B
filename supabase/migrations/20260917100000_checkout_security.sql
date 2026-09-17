-- تثبيت بيانات الطلب مرة واحدة، والتحقق من اعتماد المصنع عند الشراء.
begin;
create or replace function public.create_order_from_cart(
  p_factory_id bigint,
  p_idempotency_key uuid default gen_random_uuid()
)
returns public.orders
language plpgsql security definer set search_path = ''
as $fn$
declare
  cart_row public.carts%rowtype;
  result_row public.orders%rowtype;
  item record;
  items jsonb := '[]'::jsonb;
  price_value numeric;
  line_value numeric;
  subtotal_value numeric := 0;
  shipping_value numeric := 30;
  fee_value numeric;
  vat_value numeric;
  total_value numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_factory_id is null or p_idempotency_key is null then
    raise exception 'Factory and request key are required' using errcode = '22023';
  end if;

  -- قفل السلة يسلسل طلبات المشتري؛ إعادة المحاولة لا تعدّل طلباً سابقاً.
  select * into cart_row from public.carts where owner_id = auth.uid() for update;
  if not found then raise exception 'Cart is empty' using errcode = '22023'; end if;
  select * into result_row from public.orders
    where buyer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if found then
    if result_row.factory_id <> p_factory_id then
      raise exception 'Request key belongs to another factory' using errcode = '22023';
    end if;
    return result_row;
  end if;

  perform 1 from public.factories where id = p_factory_id and status = 'approved' for share;
  if not found then raise exception 'Factory unavailable' using errcode = '22023'; end if;

  -- تُلتقط الأسعار والكميات مرة واحدة، وتُقفل الصفوف الموجودة حتى اكتمال الطلب.
  for item in
    select ci.id as cart_item_id, ci.product_id, ci.quantity, p.factory_id, p.name,
      coalesce(cp.price, public.tier_unit_price(p.id, ci.quantity), p.price) as unit_price
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp on cp.product_id = p.id
      and cp.factory_id = p.factory_id and cp.customer_id = auth.uid()
    where ci.cart_id = cart_row.id
    order by ci.id
    for update of ci for share of p
  loop
    if item.factory_id <> p_factory_id then
      raise exception 'Create one order per factory' using errcode = '22023';
    end if;
    price_value := item.unit_price;
    if price_value is null or price_value < 0 or price_value >= 1000000000000
      or item.quantity is null or item.quantity <= 0 or item.quantity >= 1000000000 then
      raise exception 'Cart contains unavailable or unpriced products' using errcode = '22023';
    end if;
    price_value := round(price_value, 2);
    line_value := round(price_value * item.quantity, 2);
    subtotal_value := subtotal_value + line_value;
    items := items || jsonb_build_array(jsonb_build_object(
      'cart_item_id', item.cart_item_id, 'product_id', item.product_id,
      'product_name', item.name, 'unit_price', price_value,
      'quantity', item.quantity, 'line_total', line_value
    ));
  end loop;
  if jsonb_array_length(items) = 0 then
    raise exception 'Cart has no products for this factory' using errcode = '22023';
  end if;
  fee_value := round((subtotal_value + shipping_value) * 0.01, 2);
  vat_value := round((subtotal_value + shipping_value + fee_value) * 0.15, 2);
  total_value := subtotal_value + shipping_value + fee_value + vat_value;
  if total_value >= 1000000000000 then
    raise exception 'Order total is invalid' using errcode = '22023';
  end if;

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, shipping, payment_fee,
    vat_rate, vat_amount, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_payment', subtotal_value, shipping_value,
    fee_value, 0.15, vat_value, total_value, p_idempotency_key
  ) returning * into result_row;
  insert into public.order_items(order_id, product_id, product_name, unit_price, quantity, line_total)
    select result_row.id, x.product_id, x.product_name, x.unit_price, x.quantity, x.line_total
    from jsonb_to_recordset(items) as x(product_id bigint, product_name text,
      unit_price numeric, quantity numeric, line_total numeric);
  -- لا تُحذف إضافات متزامنة لم تدخل في لقطة الطلب.
  delete from public.cart_items where cart_id = cart_row.id
    and id in (select (x->>'cart_item_id')::bigint from jsonb_array_elements(items) x);
  return result_row;
end;
$fn$;
revoke all on function public.create_order_from_cart(bigint,uuid) from public, anon;
grant execute on function public.create_order_from_cart(bigint,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
