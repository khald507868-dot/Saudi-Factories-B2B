-- ============================================================
--  إضافة: المنشورات + الأسعار الخاصة
--  Supabase → SQL Editor → New query → الصق → Run
--  آمن للتشغيل أكثر من مرة.
-- ============================================================


-- ============================================================
--  1) المنشورات — posts
--  يكتبها المصنع، وتظهر في صفحته وفي الرئيسية.
-- ============================================================

create table if not exists public.posts (
  id          bigint generated always as identity primary key,
  factory_id  bigint not null references public.factories(id) on delete cascade,
  body        text not null default '',
  image       text default '',              -- رابط تخزين
  created_at  timestamptz not null default now()
);

-- الترتيب من الأحدث للأقدم — هذا ما تقرؤه الرئيسية
create index if not exists posts_created_idx on public.posts(created_at desc);
create index if not exists posts_factory_idx on public.posts(factory_id, created_at desc);

comment on table public.posts is 'منشورات المصنع — تظهر في صفحته وفي خلاصة الرئيسية';


-- ============================================================
--  2) الأسعار الخاصة — custom_prices
--  سعر يمنحه المصنع لعميل بعينه على منتج بعينه.
--  لا يراه إلا الطرفان.
-- ============================================================

create table if not exists public.custom_prices (
  id            bigint generated always as identity primary key,
  factory_id    bigint not null references public.factories(id) on delete cascade,
  product_id    bigint not null references public.products(id)  on delete cascade,
  customer_id   uuid   not null references public.profiles(id)  on delete cascade,
  price         numeric(12, 2) not null,
  note          text default '',
  created_at    timestamptz not null default now(),

  -- سعر واحد ساري لكل (منتج، عميل) — الجديد يستبدل القديم
  unique (product_id, customer_id)
);

create index if not exists custom_prices_customer_idx on public.custom_prices(customer_id);
create index if not exists custom_prices_factory_idx  on public.custom_prices(factory_id);

comment on table public.custom_prices is 'سعر خاص لعميل بعينه — تحميه RLS فلا يراه غيره';


-- ============================================================
--  3) ربط الرسالة بالسعر الخاص
--  الرسالة التي تحمل سعرًا تُعرض بشكل مميز في المحادثة.
-- ============================================================

alter table public.messages
  add column if not exists custom_price_id bigint
    references public.custom_prices(id) on delete set null;


-- ============================================================
--  4) الصلاحيات
-- ============================================================

alter table public.posts         enable row level security;
alter table public.custom_prices enable row level security;

-- ---------- posts ----------
-- تُقرأ منشورات المصانع المعتمدة فقط؛ والمالك يرى منشوراته دائمًا
drop policy if exists posts_select_public on public.posts;
create policy posts_select_public on public.posts
  for select using (
    exists (
      select 1 from public.factories f
      where f.id = posts.factory_id
        and (f.status = 'approved' or f.owner_id = auth.uid() or public.is_admin())
    )
  );

-- المصنع يكتب في منشوراته هو فقط
drop policy if exists posts_write_own on public.posts;
create policy posts_write_own on public.posts
  for all using (public.owns_factory(factory_id))
  with check (public.owns_factory(factory_id));

-- ---------- custom_prices ----------
-- الطرفان فقط: المصنع صاحب السعر، والعميل الممنوح له
drop policy if exists custom_prices_select_party on public.custom_prices;
create policy custom_prices_select_party on public.custom_prices
  for select using (
    customer_id = auth.uid() or public.owns_factory(factory_id)
  );

-- المصنع وحده يمنح السعر — والعميل لا يستطيع منح نفسه سعرًا
drop policy if exists custom_prices_write_factory on public.custom_prices;
create policy custom_prices_write_factory on public.custom_prices
  for all using (public.owns_factory(factory_id))
  with check (public.owns_factory(factory_id));


-- ============================================================
--  5) حماية الأعمدة الحساسة
--  كما في القسم 8.5 من schema.sql:
--  السياسة تتحقق ممن يعدّل لا مما يعدّل.
-- ============================================================

create or replace function public.guard_custom_price_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- لا يُنقل السعر إلى عميل آخر ولا إلى مصنع آخر بعد إنشائه
  new.factory_id  := old.factory_id;
  new.customer_id := old.customer_id;
  new.product_id  := old.product_id;
  return new;
end;
$fn$;

drop trigger if exists custom_prices_guard on public.custom_prices;
create trigger custom_prices_guard
  before update on public.custom_prices
  for each row execute function public.guard_custom_price_columns();


create or replace function public.guard_post_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  -- المنشور لا يُنسب إلى مصنع آخر
  new.factory_id := old.factory_id;
  return new;
end;
$fn$;

drop trigger if exists posts_guard on public.posts;
create trigger posts_guard
  before update on public.posts
  for each row execute function public.guard_post_columns();


-- ============================================================
--  انتهى
-- ============================================================
