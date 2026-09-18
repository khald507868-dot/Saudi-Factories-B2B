-- استعلام واحد للقراءة فقط؛ لا يعرض بيانات العملاء ولا يعدّلها.
-- passed فحص للإعداد المذكور فقط، وليس شهادة أمان شاملة.
with summary_function as (
  select p.* from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_factory_summary'
    and pg_get_function_identity_arguments(p.oid) = 'p_factory_id bigint'
), privacy_guard as (
  select p.*, pg_get_expr(p.polqual,p.polrelid) as condition
  from pg_policy p where p.polrelid = 'public.profiles'::regclass
    and p.polname = 'profiles_private_read_guard'
), certificate_policy as (
  select with_check from pg_policies where schemaname = 'storage'
    and tablename = 'objects' and policyname = 'factory_certificates_storage_add'
)
select 'summary_uses_caller_permissions' as check_name,
  coalesce((select not prosecdef from summary_function),false) as passed,
  (select jsonb_build_object('security_definer',prosecdef,'settings',proconfig)
    from summary_function) as details
union all
select 'summary_available_to_clients',
  coalesce((select has_function_privilege('anon',oid,'EXECUTE')
    and has_function_privilege('authenticated',oid,'EXECUTE') from summary_function),false),
  (select jsonb_build_object('anon',has_function_privilege('anon',oid,'EXECUTE'),
    'authenticated',has_function_privilege('authenticated',oid,'EXECUTE')) from summary_function)
union all
select 'old_profile_sharing_policy_removed',
  not exists(select 1 from pg_policies where schemaname='public' and tablename='profiles'
    and policyname='profiles_select_conversation_party'), '{}'::jsonb
union all
select 'restrictive_profile_read_guard',
  coalesce((select not polpermissive and polcmd='r' and polroles=array[0::oid] from privacy_guard),false),
  (select jsonb_build_object('condition',condition) from privacy_guard)
union all
select 'certificate_condition_uses_object_path',
  coalesce((select strpos(with_check,'split_part(objects.name,') > 0
    and strpos(with_check,'split_part(f.name,') = 0 from certificate_policy),false),
  (select jsonb_build_object('condition',with_check) from certificate_policy)
union all
select 'required_tables_have_rls', count(*)=3 and bool_and(c.relrowsecurity),
  jsonb_object_agg(c.relname,jsonb_build_object('rls',c.relrowsecurity,
    'anon_select',has_table_privilege('anon',c.oid,'SELECT'),
    'authenticated_select',has_table_privilege('authenticated',c.oid,'SELECT')))
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('profiles','factories','products');
