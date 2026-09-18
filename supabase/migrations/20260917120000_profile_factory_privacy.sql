-- معالجة نتائج تصدير الصلاحيات: خصوصية الحسابات والمصانع ومسار الشهادات.
-- لا يحذف هذا الملف سجلات أو صوراً، وهو قابل لإعادة التشغيل.
begin;

-- تعتمد دالة الملخّص على سياسات القراءة الفعلية؛ لا نواصل إذا كان RLS معطلاً.
do $do$
begin
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname in ('profiles','factories','products')
      and not c.relrowsecurity
  ) then
    raise exception 'Enable and review RLS on profiles, factories and products before applying this migration';
  end if;
end;
$do$;

-- بيانات طرف المحادثة تأتي من دوال العرض المحدودة، ولا تفتح ملفه الشخصي كله.
drop policy if exists profiles_select_conversation_party on public.profiles;
drop policy if exists profiles_private_read_guard on public.profiles;
create policy profiles_private_read_guard on public.profiles as restrictive
  for select to public
  using (id = (select auth.uid()) or (select public.is_admin()));

-- تُطبَّق RLS على المصنع ومنتجاته كما في القراءة المباشرة من الويب وFlutter.
create or replace function public.get_factory_summary(p_factory_id bigint)
returns table (is_approved boolean, product_count bigint, city text)
language sql stable security invoker set search_path = ''
as $fn$
  select (f.status = 'approved'),
         (select count(*) from public.products p where p.factory_id = f.id),
         coalesce(f.address_city, '')
    from public.factories f
   where f.id = p_factory_id;
$fn$;
revoke all on function public.get_factory_summary(bigint) from public;
grant execute on function public.get_factory_summary(bigint) to anon, authenticated;

-- name داخل استعلام المصانع كان يُفسّر كاسم المصنع، لا اسم ملف التخزين.
drop policy if exists factory_certificates_storage_add on storage.objects;
create policy factory_certificates_storage_add on storage.objects
  for insert to authenticated with check (
    bucket_id = 'factory-certificates'
    and split_part(objects.name, '/', 1) = auth.uid()::text
    and split_part(objects.name, '/', 2) = 'certificates'
    and public.account_can_write()
    and exists (
      select 1 from public.factories f
      where f.id::text = split_part(objects.name, '/', 3)
        and f.owner_id = auth.uid() and f.status = 'approved'
    )
  );

notify pgrst, 'reload schema';
commit;
