-- فحص فقط: يعرض تعريفات الدوال وسياسات الوصول والمشغلات المرتبطة بها.
-- لا يغيّر الصلاحيات أو البيانات، ولا يستدعي دوال التطبيق أو يقرأ سجلات المستخدمين.
-- شغّل في SQL Editor ثم صدّر النتائج بصيغة CSV للمراجعة.
select
  'function'::text as object_type,
  p.oid::regprocedure::text as object_name,
  pg_get_functiondef(p.oid) as definition,
  jsonb_build_object(
    'owner', pg_get_userbyid(p.proowner),
    'security_definer', p.prosecdef,
    'returns', pg_get_function_result(p.oid),
    'settings', p.proconfig,
    'anon_execute', has_function_privilege('anon', p.oid, 'execute'),
    'authenticated_execute', has_function_privilege('authenticated', p.oid, 'execute')
  ) as details
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f'

union all

select
  'policy',
  format('%I.%I / %I', schemaname, tablename, policyname),
  concat('USING: ', coalesce(qual, '(none)'), E'\nWITH CHECK: ', coalesce(with_check, '(none)')),
  jsonb_build_object('roles', roles, 'command', cmd, 'permissive', permissive)
from pg_policies
where schemaname in ('public', 'storage')

union all

select
  'trigger',
  format('%I.%I / %I', tn.nspname, c.relname, t.tgname),
  pg_get_triggerdef(t.oid),
  jsonb_build_object('function', p.oid::regprocedure::text, 'enabled', t.tgenabled)
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace tn on tn.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace pn on pn.oid = p.pronamespace
where not t.tgisinternal and pn.nspname = 'public'

order by object_type, object_name;
