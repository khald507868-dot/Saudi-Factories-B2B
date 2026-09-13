-- Read-only permission check after deployment. Does not delete any account.
select
  has_function_privilege('anon', 'public.account_deletion_media(uuid)', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.account_deletion_media(uuid)', 'execute') as authenticated_can_execute,
  has_function_privilege('service_role', 'public.account_deletion_media(uuid)', 'execute') as service_can_execute,
  p.prosecdef as security_definer,
  p.proconfig as function_settings
from pg_proc p
where p.oid = 'public.account_deletion_media(uuid)'::regprocedure;
