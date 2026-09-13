-- Schema-only deployment check: does not read or delete customer records.
select 'constraint' as kind, c.conrelid::regclass::text as relation,
       c.conname as name, pg_get_constraintdef(c.oid) as definition
from pg_constraint c
where c.contype = 'f' and c.conrelid in (
  'public.profiles'::regclass, 'public.factories'::regclass,
  'public.products'::regclass, 'public.orders'::regclass
)
union all
select 'storage_column', table_schema || '.' || table_name, column_name, data_type
from information_schema.columns
where table_schema = 'storage' and table_name = 'objects'
  and column_name in ('bucket_id', 'name', 'owner', 'owner_id')
union all
select 'function', 'public', p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('account_deletion_media', 'account_can_write')
order by kind, relation, name;
