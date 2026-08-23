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
  acct_type text;
begin
  acct_type := coalesce(new.raw_user_meta_data->>'account_type', 'individual');
  if acct_type not in ('individual', 'factory') then
    acct_type := 'individual';
  end if;

  insert into public.profiles (id, account_type, full_name, email)
  values (
    new.id,
    acct_type,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.email, '')
  )
  on conflict (id) do nothing;

  if acct_type = 'factory' then
    insert into public.factories (owner_id, name, status)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', ''),
      'pending'
    )
    on conflict (owner_id) do nothing;
  end if;

  return new;
end;
$fn$;

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
