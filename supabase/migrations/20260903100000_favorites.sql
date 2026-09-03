-- ============================================================
-- المفضّلة — جدول المنتجات التي حفظها المستخدم بزر القلب
-- تاريخ: 2026-09-03
--
-- يتبع الحساب لا المتصفّح، فتظهر المفضّلة على أي جهاز
-- يسجّل المستخدم دخوله منه.
--
-- طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
-- الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

create table if not exists public.favorites (
  id          bigint generated always as identity primary key,
  user_id     uuid   not null references public.profiles(id) on delete cascade,
  product_id  bigint not null references public.products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  -- منتج واحد لا يُحفظ مرّتين لنفس المستخدم
  unique (user_id, product_id)
);

create index if not exists favorites_user_idx
  on public.favorites(user_id, created_at desc);

alter table public.favorites enable row level security;

-- كل مستخدم يرى ويكتب مفضّلته وحده.
-- using تحكم القراءة والحذف، و with check تحكم الإضافة —
-- فبدونها يستطيع المستخدم إدراج صفّ باسم غيره.
drop policy if exists favorites_own on public.favorites;
create policy favorites_own on public.favorites
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ============================================================
-- تحقّق: يجب أن يعيد السطر التالي اسم الجدول وسياسته
-- ============================================================
select c.relname as table_name,
       p.polname as policy_name,
       c.relrowsecurity as rls_enabled
  from pg_class c
  join pg_policy p on p.polrelid = c.oid
 where c.relname = 'favorites';
