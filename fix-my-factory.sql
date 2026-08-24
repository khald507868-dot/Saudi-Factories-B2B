-- ============================================================
--  الحل الكامل: أظهر مصنعي
--
--  يعالج ثلاثة أشياء دفعةً واحدة:
--    1) يعيد تثبيت المشغّل الذي يُنشئ صفّ المصنع عند
--       التسجيل — كي لا تتكرر المشكلة مع أي حساب جديد.
--    2) يُنشئ الصفّ الناقص لحسابات المصانع الموجودة.
--    3) يعتمد مصنع المالك كي يظهر للجميع لا له وحده.
--
--  آمن للتشغيل أكثر من مرة: كل خطوة إما create or replace
--  أو on conflict do nothing أو update بشرط.
--
--  الخطوات: Supabase ← SQL Editor ← New query ← لصق ← Run
-- ============================================================


-- ===== 1) المشغّل: يُنشئ الصفّ تلقائياً لكل تسجيل جديد =====
--  هذا هو سبب المشكلة الجذري: من سجّل قبل وجود المشغّل
--  بقي حسابه بلا صفّ مصنع. نعيد تثبيته أولاً.

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


-- ===== 2) أنشئ الصفّ الناقص للحسابات الموجودة =====
insert into public.factories (owner_id, name, status)
select p.id,
       coalesce(nullif(p.full_name, ''), 'مصنعي'),
       'pending'
from public.profiles p
where p.account_type = 'factory'
  and not exists (
    select 1 from public.factories f where f.owner_id = p.id
  )
on conflict (owner_id) do nothing;


-- ===== 3) اعتمد مصنع المالك =====
--  الحارس في القاعدة يمنع المصنع من اعتماد نفسه، لكنه
--  لا يمنع تعديلاً يأتي من محرّر SQL كهذا.
--  الاسم الفارغ يُملأ كي لا تظهر البطاقة بلا عنوان.

update public.factories f
set status = 'approved',
    name   = coalesce(nullif(f.name, ''), 'مصنعي')
from public.profiles p
where p.id = f.owner_id
  and p.email = 'khald507868@gmail.com';


-- ===== 4) النتيجة =====
--  المفروض ترى صفّاً واحداً على الأقل، وفيه:
--    factory_id  = رقم (ليس فارغاً)
--    status      = approved
select p.email,
       f.id     as factory_id,
       f.name   as factory_name,
       f.status
from public.profiles p
left join public.factories f on f.owner_id = p.id
where p.account_type = 'factory'
order by p.email;
