-- Backend hardening: enforce tenant-safe custom prices, order eligibility,
-- message attachment ownership, and Storage upload limits.

-- A custom price must belong to the same factory as its product.
do $do$
begin
  if exists (
    select 1
      from public.custom_prices cp
     where not exists (
       select 1
         from public.products p
        where p.id = cp.product_id
          and p.factory_id = cp.factory_id
     )
  ) then
    raise exception 'Cannot add custom price tenant constraint: inconsistent existing data';
  end if;
end
$do$;

-- Drop the dependent foreign key before replacing the referenced unique key.
alter table public.custom_prices
  drop constraint if exists custom_prices_product_factory_fkey;

alter table public.products
  drop constraint if exists products_id_factory_uidx;
alter table public.products
  add constraint products_id_factory_uidx unique (id, factory_id);

alter table public.custom_prices
  add constraint custom_prices_product_factory_fkey
  foreign key (product_id, factory_id)
  references public.products(id, factory_id)
  on delete cascade;

alter table public.products
  drop constraint if exists products_price_nonnegative;
alter table public.products
  add constraint products_price_nonnegative
  check (price is null or price >= 0) not valid;

-- Message attachment paths must be owned by the sender. This prevents a
-- participant from pointing a message at another user's Storage object.
create or replace function public.guard_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if new.sender_id is distinct from auth.uid() then
    raise exception 'Message sender must be the authenticated user'
      using errcode = '42501';
  end if;

  if length(coalesce(new.body, '')) > 10000 then
    raise exception 'Message body is too long' using errcode = '22023';
  end if;

  if coalesce(new.attachment_url, '') = '' then
    new.attachment_url := '';
    new.attachment_type := '';
  elsif position(new.sender_id::text || '/' in new.attachment_url) <> 1 then
    raise exception 'Attachment path is not owned by sender'
      using errcode = '42501';
  elsif new.attachment_type not in ('image', 'video') then
    raise exception 'Invalid attachment type' using errcode = '22023';
  end if;

  return new;
end;
$fn$;

drop trigger if exists messages_guard_insert on public.messages;
create trigger messages_guard_insert
  before insert on public.messages
  for each row execute function public.guard_message_insert();

-- Keep the existing update guard and add the same path invariant to updates.
-- The update guard already makes attachment fields immutable.

-- Storage limits apply even when a client bypasses browser-side validation.
update storage.buckets
   set file_size_limit = 52428800,
       allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif',
                                  'video/mp4','video/webm','video/quicktime']::text[]
 where id = 'chat-media';

update storage.buckets
   set file_size_limit = 52428800,
       allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif',
                                  'video/mp4','video/webm','video/quicktime']::text[]
 where id = 'factory-media';

-- Order creation must re-check approval and pricing at checkout time.
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
  item_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_factory_id is null then
    raise exception 'Factory is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.factories
     where id = p_factory_id and status = 'approved'
  ) then
    raise exception 'Factory unavailable' using errcode = '22023';
  end if;

  select * into cart_row
    from public.carts
   where owner_id = auth.uid()
   for update;
  if not found then
    raise exception 'Cart is empty' using errcode = '22023';
  end if;

  select * into result_row
    from public.orders
   where buyer_id = auth.uid() and idempotency_key = p_idempotency_key;
  if found then return result_row; end if;

  if exists (
    select 1
      from public.cart_items ci
      join public.products p on p.id = ci.product_id
     where ci.cart_id = cart_row.id
       and (p.factory_id <> p_factory_id or p.price is null or p.price < 0)
  ) then
    raise exception 'Cart contains unavailable or unpriced products'
      using errcode = '22023';
  end if;

  select count(*), round(sum(
    ci.quantity * coalesce(cp.price, p.price)
  ), 2)
    into item_count, subtotal_value
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id
     and cp.factory_id = p.factory_id
     and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id
     and p.factory_id = p_factory_id
     and exists (
       select 1 from public.factories f
        where f.id = p.factory_id and f.status = 'approved'
     );

  if item_count = 0 then
    raise exception 'Cart has no products for this factory' using errcode = '22023';
  end if;
  if subtotal_value is null or subtotal_value > 999999999999.99 then
    raise exception 'Order total is invalid' using errcode = '22023';
  end if;

  insert into public.orders (
    buyer_id, factory_id, status, subtotal, total, idempotency_key
  ) values (
    auth.uid(), p_factory_id, 'awaiting_payment', subtotal_value, subtotal_value,
    p_idempotency_key
  ) on conflict (buyer_id, idempotency_key) do update
    set updated_at = excluded.updated_at
  returning * into result_row;

  insert into public.order_items (
    order_id, product_id, product_name, unit_price, quantity, line_total
  )
  select result_row.id, p.id, p.name,
         coalesce(cp.price, p.price), ci.quantity,
         round(coalesce(cp.price, p.price) * ci.quantity, 2)
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    left join public.custom_prices cp
      on cp.product_id = p.id
     and cp.factory_id = p.factory_id
     and cp.customer_id = auth.uid()
   where ci.cart_id = cart_row.id
     and p.factory_id = p_factory_id;

  delete from public.cart_items where cart_id = cart_row.id;
  return result_row;
end;
$fn$;

revoke all on function public.create_order_from_cart(bigint, uuid) from public;
grant execute on function public.create_order_from_cart(bigint, uuid) to authenticated;
