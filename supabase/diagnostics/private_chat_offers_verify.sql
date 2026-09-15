-- Schema/privilege verification only. No private messages, offers, or orders read.
select jsonb_build_object(
  'rls_enabled',(select relrowsecurity from pg_class where oid='public.private_chat_offers'::regclass),
  'anon_can_read',has_table_privilege('anon','public.private_chat_offers','SELECT'),
  'authenticated_can_read',has_table_privilege('authenticated','public.private_chat_offers','SELECT'),
  'authenticated_can_insert',has_table_privilege('authenticated','public.private_chat_offers','INSERT'),
  'authenticated_can_update',has_table_privilege('authenticated','public.private_chat_offers','UPDATE'),
  'authenticated_can_delete',has_table_privilege('authenticated','public.private_chat_offers','DELETE'),
  'anon_can_create',has_function_privilege('anon','public.create_private_chat_offer(bigint,bigint,integer,numeric,integer,text,uuid)','EXECUTE'),
  'authenticated_can_create',has_function_privilege('authenticated','public.create_private_chat_offer(bigint,bigint,integer,numeric,integer,text,uuid)','EXECUTE'),
  'anon_can_accept',has_function_privilege('anon','public.accept_private_chat_offer(uuid)','EXECUTE'),
  'authenticated_can_accept',has_function_privilege('authenticated','public.accept_private_chat_offer(uuid)','EXECUTE'),
  'realtime_enabled',exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='private_chat_offers' and schemaname='public')
) as checks;
