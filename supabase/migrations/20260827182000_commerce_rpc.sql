-- ============================================================
-- Cart and order RPCs
-- Prices are read from the database inside a transaction. The client
-- cannot choose the order total or unit prices.
-- ============================================================

create or replace function public.get_or_create_cart()
returns public.carts
language plpgsql
security definer
set search_path = public
as $fn$
declare result_row public.carts%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  insert into public.carts(owner_id) values (auth.uid())
  on conflict (owner_id) do update set updated_at = now()
  returning * into result_row;
  return result_row;
end;
$fn$;

create or replace function public.add_to_cart(p_product_id bigint, p_quantity numeric default 1)
returns public.cart_items
language plpgsql
security definer
set search_path = public
as $fn$
declare result_row public.cart_items%rowtype; cart_id_value bigint;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_quantity <= 0 or p_quantity > 100000 then raise exception 'Invalid quantity' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.products p join public.factories f on f.id = p.factory_id
     where p.id = p_product_id and f.status = 'approved'
  ) then raise exception 'Product unavailable' using errcode = '22023'; end if;
  select id into cart_id_value from public.get_or_create_cart();
  insert into public.cart_items(cart_id, product_id, quantity)
  values (cart_id_value, p_product_id, p_quantity)
  on conflict (cart_id, product_id) do update set quantity = cart_items.quantity + excluded.quantity
  returning * into result_row;
  return result_row;
end;
$fn$;

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
  order_id_value uuid;
  subtotal_value numeric(14,2);
  item_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_factory_id is null then raise exception 'Factory is required' using errcode = '22023'; end if;

  select * into cart_row from public.carts where owner_id = auth.uid() for update;
  if not found then raise exception 'Cart is empty' using errcode = '22023'; end if;

  select * into result_row
    from public.orders
   where buyer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if found then return result_row; end if;

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

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_payment', subtotal_value, subtotal_value, p_idempotency_key
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

revoke all on function public.get_or_create_cart() from public;
revoke all on function public.add_to_cart(bigint, numeric) from public;
revoke all on function public.create_order_from_cart(bigint, uuid) from public;
grant execute on function public.get_or_create_cart() to authenticated;
grant execute on function public.add_to_cart(bigint, numeric) to authenticated;
grant execute on function public.create_order_from_cart(bigint, uuid) to authenticated;
