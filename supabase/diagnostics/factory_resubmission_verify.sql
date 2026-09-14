select
  to_regprocedure('public.resubmit_factory_application(jsonb)') is not null as function_present,
  has_function_privilege('anon', 'public.resubmit_factory_application(jsonb)', 'execute') as anon_can_resubmit,
  has_function_privilege('authenticated', 'public.resubmit_factory_application(jsonb)', 'execute') as signed_in_can_call,
  has_function_privilege('authenticated', 'public.is_factory_resubmission(jsonb,jsonb)', 'execute') as helper_publicly_callable;
