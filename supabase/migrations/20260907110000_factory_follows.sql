-- ============================================================
--  متابعة المصانع — 2026-09-07
--
--  زرّ "متابعة" في صفحة المصنع، على نمط لينكدإن: يتابع المشتري
--  المصنع فتصله منشوراته، ويرى المصنع عدد متابعيه.
--
--  المتابعة تتبع الحساب لا المتصفّح، فتظهر على أي جهاز يسجّل
--  المستخدم دخوله منه — كالمفضّلة تماماً.
--
--  طريقة التطبيق: Supabase ← SQL Editor ← New query ← لصق ← Run
--  الملف قابل لإعادة التشغيل بأمان.
-- ============================================================

create table if not exists public.factory_follows (
  id          bigint generated always as identity primary key,
  user_id     uuid   not null references public.profiles(id) on delete cascade,
  factory_id  bigint not null references public.factories(id) on delete cascade,
  created_at  timestamptz not null default now(),
  -- مصنع واحد لا يُتابَع مرّتين من الحساب نفسه
  unique (user_id, factory_id)
);

create index if not exists factory_follows_factory_idx
  on public.factory_follows(factory_id);

alter table public.factory_follows enable row level security;


-- ------------------------------------------------------------
--  السياسات
--
--  الكتابة على صفّ المستخدم وحده: using تحكم الحذف (إلغاء
--  المتابعة) و with check تحكم الإضافة — فبدونها يستطيع
--  المستخدم إدراج متابعة باسم غيره.
--
--  ولا سياسة select هنا: العدّاد يأتي من دالّة أدناه تعمل
--  بصلاحية المالك، فلا حاجة لفتح الجدول للقراءة. وهذا أسلم —
--  قراءة الجدول مباشرةً تكشف من يتابع من.
-- ------------------------------------------------------------
drop policy if exists factory_follows_own    on public.factory_follows;
drop policy if exists factory_follows_read   on public.factory_follows;
drop policy if exists factory_follows_insert on public.factory_follows;
drop policy if exists factory_follows_delete on public.factory_follows;

create policy factory_follows_read
  on public.factory_follows for select
  using (user_id = auth.uid());

create policy factory_follows_insert
  on public.factory_follows for insert
  with check (user_id = auth.uid());

create policy factory_follows_delete
  on public.factory_follows for delete
  using (user_id = auth.uid());


-- ------------------------------------------------------------
--  عدّاد المتابعين وحالتي أنا
--
--  security definer ليقرأ الجدول كلّه ويعدّ، دون أن يفتحه
--  للقراءة المباشرة — فلا يستطيع أحد أن يعرف قائمة المتابعين،
--  ويرى الرقم فقط.
--
--  تعمل للزائر غير المسجّل أيضاً: auth.uid() تكون null فيرجع
--  is_following = false، ويُعرض العدّاد كما هو.
-- ------------------------------------------------------------
create or replace function public.get_factory_follows(p_factory_id bigint)
returns jsonb
language sql
security definer
set search_path = public
stable
as $fn$
  select jsonb_build_object(
    'followers', (
      select count(*) from public.factory_follows f
       where f.factory_id = p_factory_id
    ),
    'is_following', (
      select exists (
        select 1 from public.factory_follows f
         where f.factory_id = p_factory_id
           and f.user_id = auth.uid()
      )
    )
  );
$fn$;

revoke all on function public.get_factory_follows(bigint) from public;
grant execute on function public.get_factory_follows(bigint) to anon, authenticated;

grant select, insert, delete on public.factory_follows to authenticated;


-- ============================================================
--  تحقّق: يجب أن تظهر ثلاث سياسات على الجدول
-- ============================================================
select c.relname as table_name,
       p.polname as policy_name,
       c.relrowsecurity as rls_enabled
  from pg_class c
  join pg_policy p on p.polrelid = c.oid
 where c.relname = 'factory_follows'
 order by p.polname;
