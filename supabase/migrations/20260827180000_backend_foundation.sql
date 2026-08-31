-- ============================================================
-- Backend foundation — Saudi Factories B2B
-- Unifies the previously scattered schema additions and prepares
-- atomic factory saving, Storage, messaging, carts, and orders.
-- Safe to run repeatedly on the existing Supabase project.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Existing content tables: canonical media + stable IDs ----------
alter table public.products
  add column if not exists images text[] not null default '{}',
  add column if not exists client_key uuid not null default gen_random_uuid(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists products_client_key_uidx
  on public.products(client_key);

update public.products
   set images = array[image]
 where coalesce(image, '') <> ''
   and cardinality(images) = 0;

alter table public.products drop constraint if exists products_images_max;
alter table public.products
  add constraint products_images_max check (cardinality(images) <= 5);

create table if not exists public.posts (
  id          bigint generated always as identity primary key,
  factory_id  bigint not null references public.factories(id) on delete cascade,
  client_key  uuid not null default gen_random_uuid(),
  body        text not null default '',
  image       text not null default '',
  video       text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.posts
  add column if not exists client_key uuid not null default gen_random_uuid(),
  add column if not exists video text not null default '',
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists posts_client_key_uidx on public.posts(client_key);
create index if not exists posts_created_idx on public.posts(created_at desc);
create index if not exists posts_factory_idx on public.posts(factory_id, created_at desc);

create table if not exists public.custom_prices (
  id            bigint generated always as identity primary key,
  factory_id    bigint not null references public.factories(id) on delete cascade,
  product_id    bigint not null references public.products(id) on delete cascade,
  customer_id   uuid not null references public.profiles(id) on delete cascade,
  price         numeric(12, 2) not null check (price >= 0),
  note          text not null default '',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (product_id, customer_id)
);

alter table public.custom_prices
  add column if not exists updated_at timestamptz not null default now();

create index if not exists custom_prices_customer_idx on public.custom_prices(customer_id);
create index if not exists custom_prices_factory_idx on public.custom_prices(factory_id);

alter table public.messages
  add column if not exists custom_price_id bigint references public.custom_prices(id) on delete set null,
  add column if not exists client_key uuid not null default gen_random_uuid(),
  add column if not exists read_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists messages_client_key_uidx on public.messages(client_key);

-- ---------- Shopping cart ----------
create table if not exists public.carts (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null unique references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.cart_items (
  id          bigint generated always as identity primary key,
  cart_id     bigint not null references public.carts(id) on delete cascade,
  product_id  bigint not null references public.products(id) on delete cascade,
  quantity    numeric(12, 3) not null default 1 check (quantity > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (cart_id, product_id)
);

create index if not exists cart_items_cart_idx on public.cart_items(cart_id);

-- ---------- Orders and provider-neutral payment attempts ----------
create table if not exists public.orders (
  id                 uuid primary key default gen_random_uuid(),
  buyer_id           uuid not null references public.profiles(id) on delete restrict,
  factory_id         bigint not null references public.factories(id) on delete restrict,
  status             text not null default 'pending'
                       check (status in (
                         'pending', 'awaiting_payment', 'paid', 'processing',
                         'shipped', 'completed', 'cancelled', 'payment_failed'
                       )),
  currency           text not null default 'SAR' check (currency = 'SAR'),
  subtotal           numeric(14, 2) not null default 0 check (subtotal >= 0),
  total              numeric(14, 2) not null default 0 check (total >= 0),
  payment_provider   text not null default '',
  payment_reference  text not null default '',
  idempotency_key    uuid not null default gen_random_uuid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (buyer_id, idempotency_key)
);

create index if not exists orders_buyer_idx on public.orders(buyer_id, created_at desc);
create index if not exists orders_factory_idx on public.orders(factory_id, created_at desc);
create index if not exists orders_status_idx on public.orders(status);

create table if not exists public.order_items (
  id            bigint generated always as identity primary key,
  order_id      uuid not null references public.orders(id) on delete cascade,
  product_id    bigint references public.products(id) on delete set null,
  product_name  text not null,
  unit_price    numeric(14, 2) not null check (unit_price >= 0),
  quantity      numeric(12, 3) not null check (quantity > 0),
  line_total    numeric(14, 2) not null check (line_total >= 0),
  created_at    timestamptz not null default now()
);

create index if not exists order_items_order_idx on public.order_items(order_id);

create table if not exists public.payment_attempts (
  id                   bigint generated always as identity primary key,
  order_id             uuid not null references public.orders(id) on delete cascade,
  provider             text not null,
  provider_payment_id  text not null default '',
  status               text not null default 'created'
                         check (status in ('created', 'pending', 'paid', 'failed', 'cancelled', 'refunded')),
  amount               numeric(14, 2) not null check (amount >= 0),
  currency             text not null default 'SAR' check (currency = 'SAR'),
  raw_response         jsonb not null default '{}'::jsonb,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create unique index if not exists payment_attempts_provider_id_uidx
  on public.payment_attempts(provider, provider_payment_id)
  where provider_payment_id <> '';
create index if not exists payment_attempts_order_idx on public.payment_attempts(order_id, created_at desc);

-- ---------- Shared updated_at trigger ----------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

do $do$
declare
  table_name text;
begin
  foreach table_name in array array[
    'products', 'posts', 'custom_prices', 'messages',
    'carts', 'cart_items', 'orders', 'payment_attempts'
  ] loop
    execute format(
      'drop trigger if exists %I on public.%I',
      table_name || '_touch', table_name
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.touch_updated_at()',
      table_name || '_touch', table_name
    );
  end loop;
end;
$do$;

-- Keep the legacy scalar product image synchronized with images[1].
create or replace function public.sync_product_media()
returns trigger
language plpgsql
set search_path = public
as $fn$
begin
  if cardinality(new.images) > 0 then
    new.image := coalesce(new.images[1], '');
  elsif coalesce(new.image, '') <> '' then
    new.images := array[new.image];
  else
    new.image := '';
  end if;
  return new;
end;
$fn$;

drop trigger if exists products_sync_media on public.products;
create trigger products_sync_media
  before insert or update on public.products
  for each row execute function public.sync_product_media();

-- ---------- Access helpers ----------
create or replace function public.owns_cart(cid bigint)
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1 from public.carts c
    where c.id = cid and c.owner_id = auth.uid()
  );
$fn$;

create or replace function public.can_access_order(oid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1
      from public.orders o
      join public.factories f on f.id = o.factory_id
     where o.id = oid
       and (o.buyer_id = auth.uid() or f.owner_id = auth.uid() or public.is_admin())
  );
$fn$;

-- ---------- RLS ----------
alter table public.posts enable row level security;
alter table public.custom_prices enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payment_attempts enable row level security;

-- Profiles used in a conversation: counterpart metadata only.
drop policy if exists profiles_select_conversation_party on public.profiles;

-- Posts
drop policy if exists posts_select_public on public.posts;
create policy posts_select_public on public.posts
  for select using (
    exists (
      select 1 from public.factories f
       where f.id = posts.factory_id
         and (f.status = 'approved' or f.owner_id = auth.uid() or public.is_admin())
    )
  );

drop policy if exists posts_write_own on public.posts;
create policy posts_write_own on public.posts
  for all using (public.owns_factory(factory_id))
  with check (public.owns_factory(factory_id));

-- Custom prices
drop policy if exists custom_prices_select_party on public.custom_prices;
create policy custom_prices_select_party on public.custom_prices
  for select using (customer_id = auth.uid() or public.owns_factory(factory_id));

drop policy if exists custom_prices_write_factory on public.custom_prices;
create policy custom_prices_write_factory on public.custom_prices
  for all using (public.owns_factory(factory_id))
  with check (public.owns_factory(factory_id));

-- Carts
drop policy if exists carts_own on public.carts;
create policy carts_own on public.carts
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists cart_items_own on public.cart_items;
create policy cart_items_own on public.cart_items
  for all using (public.owns_cart(cart_id)) with check (public.owns_cart(cart_id));

-- Orders are read by the buyer, factory owner, or admin. Creation and
-- payment-status updates happen only through reviewed server functions.
drop policy if exists orders_select_party on public.orders;
create policy orders_select_party on public.orders
  for select using (public.can_access_order(id));

drop policy if exists order_items_select_party on public.order_items;
create policy order_items_select_party on public.order_items
  for select using (public.can_access_order(order_id));

drop policy if exists payment_attempts_select_party on public.payment_attempts;
create policy payment_attempts_select_party on public.payment_attempts
  for select using (public.can_access_order(order_id));

-- Messages may be marked read only by a conversation party; immutable
-- sender/conversation/body fields are enforced by a guard trigger below.
drop policy if exists messages_update_party on public.messages;
create policy messages_update_party on public.messages
  for update using (public.in_conversation(conversation_id))
  with check (public.in_conversation(conversation_id));

create or replace function public.guard_message_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  new.conversation_id := old.conversation_id;
  new.sender_id := old.sender_id;
  new.body := old.body;
  new.attachment_url := old.attachment_url;
  new.attachment_type := old.attachment_type;
  new.custom_price_id := old.custom_price_id;
  new.client_key := old.client_key;
  return new;
end;
$fn$;

drop trigger if exists messages_guard on public.messages;
create trigger messages_guard
  before update on public.messages
  for each row execute function public.guard_message_columns();

-- Factory website must be empty or HTTP(S). NOT VALID avoids blocking the
-- migration on legacy rows while enforcing the rule for future writes.
alter table public.factories drop constraint if exists factories_website_http;
alter table public.factories
  add constraint factories_website_http
  check (website = '' or website ~* '^https?://[^[:space:]]+$') not valid;

-- ---------- Storage buckets and owner-prefix policies ----------
insert into storage.buckets (id, name, public)
values ('factory-media', 'factory-media', true)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do update set public = excluded.public;

-- Public factory media: readable by all, writable only below <auth.uid()>/.
drop policy if exists factory_media_public_read on storage.objects;
create policy factory_media_public_read on storage.objects
  for select using (bucket_id = 'factory-media');

drop policy if exists factory_media_owner_insert on storage.objects;
create policy factory_media_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'factory-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists factory_media_owner_update on storage.objects;
create policy factory_media_owner_update on storage.objects
  for update to authenticated
  using (bucket_id = 'factory-media' and owner_id = auth.uid()::text)
  with check (bucket_id = 'factory-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists factory_media_owner_delete on storage.objects;
create policy factory_media_owner_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'factory-media' and owner_id = auth.uid()::text);

-- Private chat media: uploader owns the object. Access to message URLs will
-- use short-lived signed URLs after conversation authorization.
drop policy if exists chat_media_owner_insert on storage.objects;
create policy chat_media_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists chat_media_owner_select on storage.objects;
create policy chat_media_owner_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-media'
    and (
      owner_id = auth.uid()::text
      or exists (
        select 1 from public.messages m
         where m.attachment_url = name
           and public.in_conversation(m.conversation_id)
      )
    )
  );

drop policy if exists chat_media_owner_delete on storage.objects;
create policy chat_media_owner_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'chat-media' and owner_id = auth.uid()::text);

-- ---------- Grants ----------
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.carts, public.cart_items to authenticated;
grant select on public.orders, public.order_items, public.payment_attempts to authenticated;
grant select, insert, update, delete on public.posts, public.custom_prices to authenticated;
grant select, insert, update on public.messages to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Optional realtime publication for messages. Idempotent across projects.
do $do$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'messages'
     ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$do$;
