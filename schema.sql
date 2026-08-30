-- ============================================================
--  مخطط قاعدة البيانات — دليل المصانع السعودية
--  Supabase / PostgreSQL
--
--  طريقة الاستخدام:
--    Supabase → SQL Editor → New query → الصق هذا الملف كاملًا → Run
--    يمكن تشغيله أكثر من مرة بأمان.
-- ============================================================


-- ============================================================
--  1) الحسابات — profiles
--  يرتبط كل سجل بحساب مصادقة في auth.users (يديره Supabase).
--  كلمات المرور لا تُخزَّن هنا إطلاقًا — Supabase يتولاها مشفّرة.
-- ============================================================

create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  account_type   text not null default 'individual'
                   check (account_type in ('individual', 'factory')),
  full_name      text not null default '',
  gender         text default '',          -- للأفراد فقط
  country_flag   text default '',
  country_code   text default '',
  phone          text default '',
  email          text default '',
  birthdate      date,                     -- من profile.html فقط
  company_image  text default '',          -- رابط في التخزين (ليس base64)
  is_admin       boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table  public.profiles is 'بيانات الحساب — تقابل مفتاح sf_account السابق';
comment on column public.profiles.is_admin is 'صلاحية الإدارة — تُمنح يدويًا من لوحة Supabase فقط';


-- ============================================================
--  2) المصانع — factories
--  كل مصنع مملوك لحساب واحد عبر owner_id.
--  هذا هو الحقل الذي يغلق ثغرة "أي مصنع يعدّل أي صفحة".
-- ============================================================

create table if not exists public.factories (
  id                  bigint generated always as identity primary key,
  owner_id            uuid not null unique
                        references public.profiles(id) on delete cascade,

  -- الحالة: يبني المصنع صفحته أثناء pending، ولا تظهر للعامة إلا عند approved
  status              text not null default 'pending'
                        check (status in ('pending', 'approved', 'rejected')),
  rejection_reason    text default '',

  name                text not null default '',
  about               text not null default '',
  cover               text default '',      -- رابط تخزين
  logo                text default '',      -- رابط تخزين

  commercial_register text not null default '',   -- 10 أرقام حدّاً أقصى
  industrial_license  text not null default '',   -- 10 أرقام حدّاً أقصى
  region_id           text default '',      -- يقابل معرّفات مناطق regions-geo.js
  website             text not null default '',
  industry            text not null default '',   -- يقابل فئات i18n.js
  company_size        text not null default '',   -- نطاق مثل 51-200

  -- العنوان الوطني — مفكوك إلى أعمدة بدل كائن JSON
  address_city        text default '',
  address_district    text default '',
  address_short       text default '',      -- ABCD1234
  address_building    text default '',      -- 4 أرقام
  address_secondary   text default '',      -- 4 أرقام
  address_postal      text default '',      -- 5 أرقام
  address_street      text default '',

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists factories_status_idx  on public.factories(status);
create index if not exists factories_region_idx  on public.factories(region_id);
create index if not exists factories_owner_idx   on public.factories(owner_id);

comment on column public.factories.owner_id is 'حساب واحد = مصنع واحد (unique)';
comment on column public.factories.status   is 'pending عند التسجيل، approved بعد موافقة الإدارة';


-- ============================================================
--  3) المنتجات — products
--  كانت مصفوفة داخل سجل المصنع، وأصبحت جدولًا مستقلًا
--  ليصبح البحث والترتيب ممكنًا.
-- ============================================================

create table if not exists public.products (
  id          bigint generated always as identity primary key,
  factory_id  bigint not null references public.factories(id) on delete cascade,
  image       text default '',
  name        text not null default '',
  price       numeric(12, 2),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists products_factory_idx on public.products(factory_id);


-- ============================================================
--  4) المحادثات — conversations + messages
--  محادثة واحدة بين فرد ومصنع.
-- ============================================================

create table if not exists public.conversations (
  id              bigint generated always as identity primary key,
  factory_id      bigint not null references public.factories(id) on delete cascade,
  individual_id   uuid  not null references public.profiles(id)  on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (factory_id, individual_id)
);

create index if not exists conversations_factory_idx    on public.conversations(factory_id);
create index if not exists conversations_individual_idx on public.conversations(individual_id);

create table if not exists public.messages (
  id              bigint generated always as identity primary key,
  conversation_id bigint not null references public.conversations(id) on delete cascade,
  sender_id       uuid   not null references public.profiles(id)      on delete cascade,
  body            text default '',
  attachment_url  text default '',
  attachment_type text default ''
                    check (attachment_type in ('', 'image', 'video')),
  created_at      timestamptz not null default now()
);

create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);


-- ============================================================
--  5) دوال مساعدة
--  security definer لتجاوز RLS داخل الدالة وتفادي العودية اللانهائية
--  عند استدعائها من داخل سياسات الجداول نفسها.
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$fn$;

create or replace function public.owns_factory(fid bigint)
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1 from public.factories
    where id = fid and owner_id = auth.uid()
  );
$fn$;

create or replace function public.in_conversation(cid bigint)
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1
    from public.conversations c
    join public.factories f on f.id = c.factory_id
    where c.id = cid
      and (c.individual_id = auth.uid() or f.owner_id = auth.uid())
  );
$fn$;


-- ============================================================
--  6) إنشاء الملف الشخصي تلقائيًا عند التسجيل
--  عند إنشاء حساب من نوع مصنع، يُنشأ سجل المصنع في نفس اللحظة
--  بحالة pending.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  meta      jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  acct_type text;
begin
  acct_type := coalesce(meta->>'account_type', 'individual');
  if acct_type not in ('individual', 'factory') then
    acct_type := 'individual';
  end if;

  insert into public.profiles (
    id, account_type, full_name, gender,
    country_flag, country_code, phone, email
  )
  values (
    new.id,
    acct_type,
    coalesce(meta->>'full_name', ''),
    coalesce(meta->>'gender', ''),
    coalesce(meta->>'country_flag', ''),
    coalesce(meta->>'country_code', ''),
    coalesce(meta->>'phone', ''),
    coalesce(new.email, '')
  )
  on conflict (id) do update set
    full_name    = excluded.full_name,
    gender       = excluded.gender,
    country_flag = excluded.country_flag,
    country_code = excluded.country_code,
    phone        = excluded.phone,
    email        = excluded.email;

  if acct_type = 'factory' then
    insert into public.factories (
      owner_id, name, status,
      commercial_register, industrial_license,
      address_city, address_district, address_short,
      address_building, address_secondary,
      address_postal, address_street
    )
    values (
      new.id,
      coalesce(meta->>'full_name', ''),
      'pending',
      coalesce(meta->>'commercial_register', ''),
      coalesce(meta->>'industrial_license', ''),
      coalesce(meta->>'address_city', ''),
      coalesce(meta->>'address_district', ''),
      coalesce(meta->>'address_short', ''),
      coalesce(meta->>'address_building', ''),
      coalesce(meta->>'address_secondary', ''),
      coalesce(meta->>'address_postal', ''),
      coalesce(meta->>'address_street', '')
    )
    on conflict (owner_id) do update set
      name                = excluded.name,
      commercial_register = excluded.commercial_register,
      industrial_license  = excluded.industrial_license,
      address_city        = excluded.address_city,
      address_district    = excluded.address_district,
      address_short       = excluded.address_short,
      address_building    = excluded.address_building,
      address_secondary   = excluded.address_secondary,
      address_postal      = excluded.address_postal,
      address_street      = excluded.address_street;
  end if;

  return new;
end;
$fn$;

comment on function public.handle_new_user()
  is 'ينشئ بيانات التسجيل الأولية خادميًا ويعمل مع تأكيد البريد دون جلسة متصفح';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
--  7) تحديث updated_at تلقائيًا
-- ============================================================

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists profiles_touch  on public.profiles;
create trigger profiles_touch  before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists factories_touch on public.factories;
create trigger factories_touch before update on public.factories
  for each row execute function public.touch_updated_at();


-- ============================================================
--  8) الصلاحيات — Row Level Security
--  هذه هي الحماية الحقيقية. تُطبَّق في الخادم،
--  ولا يستطيع أحد تجاوزها بتعديل JavaScript أو localStorage.
-- ============================================================

alter table public.profiles      enable row level security;
alter table public.factories     enable row level security;
alter table public.products      enable row level security;
alter table public.conversations enable row level security;
alter table public.messages      enable row level security;

-- ---------- profiles ----------
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ---------- factories ----------
-- العامة ترى المصانع المعتمدة فقط؛ المالك يرى مصنعه في كل الحالات
drop policy if exists factories_select_public on public.factories;
create policy factories_select_public on public.factories
  for select using (
    status = 'approved'
    or owner_id = auth.uid()
    or public.is_admin()
  );

-- المالك يعدّل مصنعه هو فقط — هذا ما يغلق الثغرة الحالية
drop policy if exists factories_update_own on public.factories;
create policy factories_update_own on public.factories
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- الإدارة وحدها تغيّر الحالة (القبول/الرفض)
drop policy if exists factories_update_admin on public.factories;
create policy factories_update_admin on public.factories
  for update using (public.is_admin()) with check (public.is_admin());

-- ---------- products ----------
drop policy if exists products_select_public on public.products;
create policy products_select_public on public.products
  for select using (
    exists (
      select 1 from public.factories f
      where f.id = products.factory_id
        and (f.status = 'approved' or f.owner_id = auth.uid() or public.is_admin())
    )
  );

drop policy if exists products_write_own on public.products;
create policy products_write_own on public.products
  for all using (public.owns_factory(factory_id))
  with check (public.owns_factory(factory_id));

-- ---------- conversations ----------
drop policy if exists conversations_select_party on public.conversations;
create policy conversations_select_party on public.conversations
  for select using (
    individual_id = auth.uid() or public.owns_factory(factory_id)
  );

drop policy if exists conversations_insert_individual on public.conversations;
create policy conversations_insert_individual on public.conversations
  for insert with check (individual_id = auth.uid());

-- ---------- messages ----------
drop policy if exists messages_select_party on public.messages;
create policy messages_select_party on public.messages
  for select using (public.in_conversation(conversation_id));

-- المرسل هو صاحب الحساب، وهو طرف في المحادثة
drop policy if exists messages_insert_party on public.messages;
create policy messages_insert_party on public.messages
  for insert with check (
    sender_id = auth.uid() and public.in_conversation(conversation_id)
  );

-- ============================================================
--  8.5) حماية الأعمدة الحساسة
--  RLS تتحقق ممن يعدل، لا مما يعدل — فبدون هذه المشغلات
--  يستطيع اي مستخدم كتابة is_admin=true او status=approved.
--  (كشف بالاختبار الفعلي، لا بالمراجعة النظرية)
-- ============================================================

-- ---------- حماية is_admin ----------
create or replace function public.guard_profile_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- المدير وحده يمنح صلاحية الإدارة
  if new.is_admin is distinct from old.is_admin then
    if not public.is_admin() then
      new.is_admin := old.is_admin;
    end if;
  end if;

  -- نوع الحساب لا يتغيّر بعد التسجيل
  new.account_type := old.account_type;
  new.id           := old.id;

  return new;
end;
$fn$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_columns();


-- ---------- حماية status ----------
create or replace function public.guard_factory_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- الإدارة وحدها تعتمد أو ترفض
  if new.status is distinct from old.status then
    if not public.is_admin() then
      new.status := old.status;
    end if;
  end if;

  if new.rejection_reason is distinct from old.rejection_reason then
    if not public.is_admin() then
      new.rejection_reason := old.rejection_reason;
    end if;
  end if;

  -- الملكية لا تُنقل
  new.owner_id := old.owner_id;

  return new;
end;
$fn$;

drop trigger if exists factories_guard on public.factories;
create trigger factories_guard
  before update on public.factories
  for each row execute function public.guard_factory_columns();



-- ============================================================
--  9) التخزين — الصور
--  المجلدات تُنشأ هنا؛ سياساتها تُضبط في مرحلة الصور لاحقًا.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('factory-media', 'factory-media', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- ============================================================
--  انتهى
-- ============================================================


-- ============================================================
-- 10) الترحيلات الموحدة للباك إند
-- ============================================================
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
create policy profiles_select_conversation_party on public.profiles
  for select using (
    id = auth.uid()
    or exists (
      select 1
        from public.conversations c
        join public.factories f on f.id = c.factory_id
       where c.individual_id = profiles.id
         and (c.individual_id = auth.uid() or f.owner_id = auth.uid())
    )
    or public.is_admin()
  );

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


-- ============================================================
-- 11) الحفظ الذري للمصنع
-- ============================================================
-- ============================================================
-- Atomic factory editor save
-- One authenticated RPC updates the factory, products, and posts
-- in a single PostgreSQL transaction. Stable client_key values avoid
-- delete/reinsert cycles and preserve references.
-- ============================================================

create or replace function public.save_factory_content(
  p_factory_id bigint,
  p_factory jsonb,
  p_products jsonb default null,
  p_posts jsonb default null,
  p_expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  current_row public.factories%rowtype;
  item jsonb;
  item_key uuid;
  product_keys uuid[] := '{}';
  post_keys uuid[] := '{}';
  clean_images text[];
  clean_price numeric(12, 2);
  result_row jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if jsonb_typeof(coalesce(p_factory, '{}'::jsonb)) <> 'object'
     or (p_products is not null and jsonb_typeof(p_products) <> 'array')
     or (p_posts is not null and jsonb_typeof(p_posts) <> 'array') then
    raise exception 'Invalid factory payload' using errcode = '22023';
  end if;

  if (p_products is not null and jsonb_array_length(p_products) > 200)
     or (p_posts is not null and jsonb_array_length(p_posts) > 500) then
    raise exception 'Payload exceeds allowed item count' using errcode = '22023';
  end if;

  -- Serialize edits for one factory and lock the owner row.
  perform pg_advisory_xact_lock(p_factory_id);
  select * into current_row
    from public.factories
   where id = p_factory_id
     and owner_id = auth.uid()
   for update;

  if not found then
    raise exception 'Factory not found or not owned by current user'
      using errcode = '42501';
  end if;

  if p_expected_updated_at is not null
     and current_row.updated_at is distinct from p_expected_updated_at then
    raise exception 'Factory data changed in another session; reload before saving'
      using errcode = '40001';
  end if;

  if coalesce(p_factory->>'website', '') <> ''
     and coalesce(p_factory->>'website', '') !~* '^https?://[^[:space:]]+$' then
    raise exception 'Website must use http or https' using errcode = '22023';
  end if;

  update public.factories
     set name = case when p_factory ? 'name' then left(coalesce(p_factory->>'name', ''), 200) else current_row.name end,
         about = case when p_factory ? 'about' then left(coalesce(p_factory->>'about', ''), 10000) else current_row.about end,
         cover = case when p_factory ? 'cover' then left(coalesce(p_factory->>'cover', ''), 2048) else current_row.cover end,
         logo = case when p_factory ? 'logo' then left(coalesce(p_factory->>'logo', ''), 2048) else current_row.logo end,
         website = case when p_factory ? 'website' then left(coalesce(p_factory->>'website', ''), 2048) else current_row.website end,
         industry = case when p_factory ? 'industry' then left(coalesce(p_factory->>'industry', ''), 200) else current_row.industry end,
         company_size = case when p_factory ? 'company_size' then left(coalesce(p_factory->>'company_size', ''), 100) else current_row.company_size end
   where id = p_factory_id;

  -- Upsert products by stable client_key. NULL means “leave unchanged”.
  if p_products is not null then
  for item in select value from jsonb_array_elements(p_products) loop
    begin
      item_key := nullif(item->>'client_key', '')::uuid;
    exception when invalid_text_representation then
      item_key := null;
    end;

    if item_key is null
       or exists (
         select 1 from public.products p
          where p.client_key = item_key and p.factory_id <> p_factory_id
       ) then
      item_key := gen_random_uuid();
    end if;

    select coalesce(array_agg(left(value, 2048)), '{}')
      into clean_images
      from (
        select value
          from jsonb_array_elements_text(
            case when jsonb_typeof(item->'images') = 'array'
                 then item->'images' else '[]'::jsonb end
          )
         where value <> ''
         limit 5
      ) image_values;

    if coalesce(item->>'price', '') ~ '^[0-9]+([.][0-9]{1,2})?$' then
      clean_price := (item->>'price')::numeric(12, 2);
    else
      clean_price := null;
    end if;

    insert into public.products (
      factory_id, client_key, images, image, name, price, sort_order
    ) values (
      p_factory_id,
      item_key,
      clean_images,
      coalesce(clean_images[1], ''),
      left(coalesce(item->>'name', ''), 300),
      clean_price,
      coalesce(array_length(product_keys, 1), 0)
    )
    on conflict (client_key) do update
       set images = excluded.images,
           image = excluded.image,
           name = excluded.name,
           price = excluded.price,
           sort_order = excluded.sort_order
     where products.factory_id = p_factory_id;

    product_keys := array_append(product_keys, item_key);
  end loop;

  delete from public.products
   where factory_id = p_factory_id
     and not (client_key = any(product_keys));
  end if;

  -- Upsert posts by stable client_key. NULL means “leave unchanged”.
  if p_posts is not null then
  for item in select value from jsonb_array_elements(p_posts) loop
    begin
      item_key := nullif(item->>'client_key', '')::uuid;
    exception when invalid_text_representation then
      item_key := null;
    end;

    if item_key is null
       or exists (
         select 1 from public.posts p
          where p.client_key = item_key and p.factory_id <> p_factory_id
       ) then
      item_key := gen_random_uuid();
    end if;

    insert into public.posts (
      factory_id, client_key, body, image, video
    ) values (
      p_factory_id,
      item_key,
      left(coalesce(item->>'body', ''), 10000),
      left(coalesce(item->>'image', ''), 2048),
      left(coalesce(item->>'video', ''), 2048)
    )
    on conflict (client_key) do update
       set body = excluded.body,
           image = excluded.image,
           video = excluded.video
     where posts.factory_id = p_factory_id;

    post_keys := array_append(post_keys, item_key);
  end loop;

  delete from public.posts
   where factory_id = p_factory_id
     and not (client_key = any(post_keys));
  end if;

  select jsonb_build_object(
    'factory', to_jsonb(f),
    'products', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.sort_order)
        from public.products p where p.factory_id = p_factory_id
    ), '[]'::jsonb),
    'posts', coalesce((
      select jsonb_agg(to_jsonb(po) order by po.created_at desc)
        from public.posts po where po.factory_id = p_factory_id
    ), '[]'::jsonb)
  ) into result_row
  from public.factories f
  where f.id = p_factory_id;

  return result_row;
end;
$fn$;

revoke all on function public.save_factory_content(bigint, jsonb, jsonb, jsonb, timestamptz) from public;
grant execute on function public.save_factory_content(bigint, jsonb, jsonb, jsonb, timestamptz) to authenticated;

comment on function public.save_factory_content(bigint, jsonb, jsonb, jsonb, timestamptz)
  is 'Atomically saves one owned factory and upserts products/posts by stable client keys';


-- ============================================================
-- 12) السلة والطلبات والتحقق السعري الخادمي
-- ============================================================
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


-- ============================================================
--  14) إكمال ربط الرسائل الفورية
-- ============================================================

grant select, insert on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant usage, select on all sequences in schema public to authenticated;

drop policy if exists conversations_insert_individual on public.conversations;
create policy conversations_insert_individual on public.conversations
  for insert to authenticated
  with check (
    individual_id = auth.uid()
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and p.account_type = 'individual'
    )
    and exists (
      select 1 from public.factories f
       where f.id = factory_id
         and f.status = 'approved'
    )
  );

create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.conversations
     set last_message_at = greatest(last_message_at, new.created_at)
   where id = new.conversation_id;
  return new;
end;
$fn$;

drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation_from_message();

revoke all on function public.touch_conversation_from_message() from public;

create or replace function public.get_conversation_peers()
returns table (
  conversation_id bigint,
  peer_name text,
  peer_avatar text,
  peer_role text
)
language sql
security definer
set search_path = public
stable
as $fn$
  select
    c.id,
    case when c.individual_id = auth.uid()
      then coalesce(f.name, '')
      else coalesce(p.full_name, '')
    end,
    case when c.individual_id = auth.uid()
      then coalesce(f.logo, '')
      else coalesce(p.company_image, '')
    end,
    case when c.individual_id = auth.uid()
      then 'factory'::text
      else 'individual'::text
    end
  from public.conversations c
  join public.factories f on f.id = c.factory_id
  join public.profiles p on p.id = c.individual_id
  where c.individual_id = auth.uid()
     or f.owner_id = auth.uid();
$fn$;

revoke all on function public.get_conversation_peers() from public;
grant execute on function public.get_conversation_peers() to authenticated;


-- ============================================================
--  15) ملخصات المحادثات وعدّاد الرسائل غير المقروءة
-- ============================================================

alter table public.messages
  add column if not exists read_at timestamptz;

create index if not exists messages_unread_conversation_idx
  on public.messages(conversation_id, sender_id)
  where read_at is null;

create index if not exists conversations_individual_recent_idx
  on public.conversations(individual_id, last_message_at desc);

drop policy if exists messages_update_party on public.messages;
create policy messages_update_party on public.messages
  for update to authenticated
  using (
    public.in_conversation(conversation_id)
    and sender_id <> auth.uid()
  )
  with check (
    public.in_conversation(conversation_id)
    and sender_id <> auth.uid()
  );

create or replace function public.get_conversation_summaries()
returns table (
  conversation_id bigint,
  factory_id bigint,
  individual_id uuid,
  peer_name text,
  peer_avatar text,
  peer_role text,
  last_message_body text,
  last_message_type text,
  last_message_created_at timestamptz,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  unread_count bigint
)
language sql
security definer
set search_path = public
stable
as $fn$
  select
    c.id,
    c.factory_id,
    c.individual_id,
    case when c.individual_id = auth.uid()
      then coalesce(f.name, '')
      else coalesce(p.full_name, '')
    end,
    case when c.individual_id = auth.uid()
      then coalesce(f.logo, '')
      else coalesce(p.company_image, '')
    end,
    case when c.individual_id = auth.uid()
      then 'factory'::text
      else 'individual'::text
    end,
    coalesce(lm.body, ''),
    coalesce(lm.attachment_type, ''),
    lm.created_at,
    lm.sender_id,
    c.last_message_at,
    (
      select count(*)
        from public.messages unread
       where unread.conversation_id = c.id
         and unread.sender_id <> auth.uid()
         and unread.read_at is null
    )
  from public.conversations c
  join public.factories f on f.id = c.factory_id
  join public.profiles p on p.id = c.individual_id
  left join lateral (
    select m.body, m.attachment_type, m.created_at, m.sender_id
      from public.messages m
     where m.conversation_id = c.id
     order by m.created_at desc, m.id desc
     limit 1
  ) lm on true
  where c.individual_id = auth.uid()
     or f.owner_id = auth.uid()
  order by coalesce(lm.created_at, c.created_at) desc, c.id desc;
$fn$;

revoke all on function public.get_conversation_summaries() from public;
grant execute on function public.get_conversation_summaries() to authenticated;

create or replace function public.mark_conversation_read(p_conversation_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  affected integer := 0;
begin
  if auth.uid() is null or not public.in_conversation(p_conversation_id) then
    raise exception 'Conversation access denied' using errcode = '42501';
  end if;

  update public.messages
     set read_at = now()
   where conversation_id = p_conversation_id
     and sender_id <> auth.uid()
     and read_at is null;

  get diagnostics affected = row_count;
  return affected;
end;
$fn$;

revoke all on function public.mark_conversation_read(bigint) from public;
grant execute on function public.mark_conversation_read(bigint) to authenticated;


-- ============================================================
--  16) إجمالي الرسائل غير المقروءة لأيقونة الرسائل
-- ============================================================

create or replace function public.get_unread_message_total()
returns bigint
language sql
security definer
set search_path = public
stable
as $fn$
  select count(*)
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
    join public.factories f on f.id = c.factory_id
   where m.sender_id <> auth.uid()
     and m.read_at is null
     and (
       c.individual_id = auth.uid()
       or f.owner_id = auth.uid()
     );
$fn$;

revoke all on function public.get_unread_message_total() from public;
grant execute on function public.get_unread_message_total() to authenticated;
