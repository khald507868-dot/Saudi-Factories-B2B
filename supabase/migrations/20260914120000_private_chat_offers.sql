-- Private, single-use negotiated offers. Public product prices are never changed.
begin;
create table if not exists public.private_chat_offers (
  id uuid primary key default gen_random_uuid(),
  conversation_id bigint not null references public.conversations(id) on delete cascade,
  message_id bigint not null unique references public.messages(id) on delete cascade,
  factory_id bigint not null references public.factories(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  product_id bigint references public.products(id) on delete set null,
  product_name text not null,
  product_image text not null default '',
  quantity integer not null check(quantity between 1 and 100000),
  unit_price numeric(14,2) not null check(unit_price > 0 and unit_price <= 1000000),
  currency text not null default 'SAR' check(currency = 'SAR'),
  subtotal numeric(14,2) not null,
  shipping numeric(14,2) not null,
  payment_fee numeric(14,2) not null,
  vat_rate numeric(5,4) not null,
  vat_amount numeric(14,2) not null,
  total numeric(14,2) not null,
  notes text not null default '' check(length(notes) <= 1000),
  valid_days integer not null check(valid_days between 1 and 30),
  expires_at timestamptz not null,
  status text not null default 'pending' check(status in ('pending','accepted','declined','withdrawn')),
  order_id uuid unique references public.orders(id) on delete restrict,
  request_key uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(seller_id, request_key),
  check(buyer_id <> seller_id),
  check((status = 'accepted') = (order_id is not null))
);
create index if not exists private_chat_offers_conversation_idx on public.private_chat_offers(conversation_id, created_at);
alter table public.private_chat_offers enable row level security;
revoke all on public.private_chat_offers from public, anon, authenticated;
grant select on public.private_chat_offers to authenticated;
drop policy if exists private_chat_offers_parties on public.private_chat_offers;
create policy private_chat_offers_parties on public.private_chat_offers for select to authenticated
  using (auth.uid() = buyer_id or auth.uid() = seller_id);

create or replace function public.create_private_chat_offer(
  p_conversation_id bigint, p_product_id bigint, p_quantity integer,
  p_unit_price numeric, p_valid_days integer, p_notes text, p_request_key uuid
) returns public.private_chat_offers language plpgsql security definer set search_path = '' as $$
declare
  c public.conversations%rowtype;
  f public.factories%rowtype;
  p public.products%rowtype;
  q public.private_chat_offers%rowtype;
  mid bigint;
  sub numeric(14,2); fee numeric(14,2); vat numeric(14,2);
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity not between 1 and 100000
    or p_unit_price is null or p_unit_price <= 0 or p_unit_price > 1000000
    or p_unit_price <> round(p_unit_price,2) or p_valid_days is null or p_valid_days not between 1 and 30
    or p_request_key is null or length(coalesce(p_notes,'')) > 1000 then
    raise exception 'offer_invalid' using errcode = '22023';
  end if;
  select * into c from public.conversations where id = p_conversation_id;
  select * into f from public.factories where id = c.factory_id for share;
  if c.id is null or f.owner_id is distinct from auth.uid() or f.status <> 'approved'
    or c.individual_id = auth.uid() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  -- Serialize retries of the same draft, including two simultaneous requests.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_request_key::text, 0));
  select * into q from public.private_chat_offers where seller_id = auth.uid() and request_key = p_request_key;
  if found then
    if q.conversation_id <> p_conversation_id or q.product_id is distinct from p_product_id
      or q.quantity <> p_quantity or q.unit_price <> p_unit_price or q.valid_days <> p_valid_days
      or q.notes <> btrim(coalesce(p_notes,'')) then
      raise exception 'offer_invalid' using errcode = '22023';
    end if;
    return q;
  end if;
  select * into p from public.products where id = p_product_id and factory_id = f.id for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  sub := p_quantity * p_unit_price;
  -- Match the platform's existing checkout charges, frozen for this offer.
  fee := round((sub + 30) * 0.01, 2);
  vat := round((sub + 30 + fee) * 0.15, 2);
  insert into public.messages(conversation_id, sender_id, body)
    values(c.id, auth.uid(), 'عرض سعر خاص / Private offer: ' || left(p.name, 200)) returning id into mid;
  insert into public.private_chat_offers(
    conversation_id, message_id, factory_id, seller_id, buyer_id, product_id, product_name, product_image,
    quantity, unit_price, subtotal, shipping, payment_fee, vat_rate, vat_amount, total,
    valid_days, expires_at, notes, request_key
  ) values (
    c.id, mid, f.id, auth.uid(), c.individual_id, p.id, p.name,
    coalesce(nullif(p.images[1],''), p.image, ''),
    p_quantity, p_unit_price, sub, 30, fee, 0.15, vat, sub + 30 + fee + vat,
    p_valid_days, clock_timestamp() + make_interval(days => p_valid_days), btrim(coalesce(p_notes,'')), p_request_key
  ) returning * into q;
  return q;
end;
$$;

create or replace function public.accept_private_chat_offer(p_offer_id uuid)
returns public.private_chat_offers language plpgsql security definer set search_path = '' as $$
declare q public.private_chat_offers%rowtype; oid uuid;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  select * into q from public.private_chat_offers where id = p_offer_id and buyer_id = auth.uid() for update;
  if not found then raise exception 'offer_access_denied' using errcode = '42501'; end if;
  -- One offer creates at most one order, even after a timeout or double click.
  if q.status = 'accepted' then return q; end if;
  if q.status <> 'pending' or q.expires_at <= clock_timestamp() then
    raise exception 'offer_unavailable' using errcode = '22023';
  end if;
  perform 1 from public.factories where id = q.factory_id and owner_id = q.seller_id and status = 'approved' for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  perform 1 from public.products where id = q.product_id and factory_id = q.factory_id for share;
  if not found then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  insert into public.orders(buyer_id, factory_id, status, currency, subtotal, shipping, payment_fee, vat_rate, vat_amount, total)
    values(q.buyer_id, q.factory_id, 'awaiting_payment', q.currency, q.subtotal, q.shipping, q.payment_fee, q.vat_rate, q.vat_amount, q.total)
    returning id into oid;
  insert into public.order_items(order_id, product_id, product_name, unit_price, quantity, line_total)
    values(oid, q.product_id, q.product_name, q.unit_price, q.quantity, q.subtotal);
  update public.private_chat_offers set status = 'accepted', order_id = oid, updated_at = clock_timestamp()
    where id = q.id returning * into q;
  return q;
end;
$$;

create or replace function public.close_private_chat_offer(p_offer_id uuid, p_action text)
returns public.private_chat_offers language plpgsql security definer set search_path = '' as $$
declare q public.private_chat_offers%rowtype;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'offer_access_denied' using errcode = '42501';
  end if;
  select * into q from public.private_chat_offers where id = p_offer_id and
    ((p_action = 'declined' and buyer_id = auth.uid()) or (p_action = 'withdrawn' and seller_id = auth.uid())) for update;
  if not found then raise exception 'offer_access_denied' using errcode = '42501'; end if;
  if q.status = p_action then return q; end if;
  if q.status <> 'pending' then raise exception 'offer_unavailable' using errcode = '22023'; end if;
  update public.private_chat_offers set status = p_action, updated_at = clock_timestamp() where id = q.id returning * into q;
  return q;
end;
$$;

revoke all on function public.create_private_chat_offer(bigint,bigint,integer,numeric,integer,text,uuid) from public, anon;
revoke all on function public.accept_private_chat_offer(uuid) from public, anon;
revoke all on function public.close_private_chat_offer(uuid,text) from public, anon;
grant execute on function public.create_private_chat_offer(bigint,bigint,integer,numeric,integer,text,uuid) to authenticated;
grant execute on function public.accept_private_chat_offer(uuid) to authenticated;
grant execute on function public.close_private_chat_offer(uuid,text) to authenticated;
drop trigger if exists account_approval_write_guard on public.private_chat_offers;
create trigger account_approval_write_guard before insert or update or delete on public.private_chat_offers
  for each row execute function public.require_approved_account_write();
do $$ begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') and not exists(
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'private_chat_offers'
  ) then alter publication supabase_realtime add table public.private_chat_offers; end if;
end $$;
notify pgrst, 'reload schema';
commit;
