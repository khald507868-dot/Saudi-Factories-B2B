select jsonb_build_object(
  'rls_enabled',(select relrowsecurity from pg_class where oid='public.factory_certificates'::regclass),
  'public_read',has_table_privilege('anon','public.factory_certificates','SELECT'),
  'public_insert',has_table_privilege('anon','public.factory_certificates','INSERT'),
  'authenticated_insert',has_table_privilege('authenticated','public.factory_certificates','INSERT'),
  'authenticated_update',has_table_privilege('authenticated','public.factory_certificates','UPDATE'),
  'authenticated_delete',has_table_privilege('authenticated','public.factory_certificates','DELETE'),
  'bucket',(select jsonb_build_object('public',public,'max_bytes',file_size_limit,'mime_types',allowed_mime_types) from storage.buckets where id='factory-certificates'),
  'policies',(select jsonb_agg(jsonb_build_object('name',policyname,'command',cmd,'kind',permissive)) from pg_policies where tablename='factory_certificates' or policyname like 'factory_certificates_storage_%'),
  'validation_trigger',exists(select 1 from pg_trigger where tgrelid='public.factory_certificates'::regclass and tgname='factory_certificate_image_guard')
);
