-- تحقق للقراءة فقط بعد تطبيق الهجرة. جميع النتائج يجب أن تكون true.
select 'shipping_tables_rls' as check_name,
  count(*)=4 and bool_and(c.relrowsecurity) as passed
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('order_shipments','shipping_quotes','shipping_events','shipping_notifications')
union all
select 'no_direct_client_writes', not exists(
  select 1 from unnest(array['order_shipments','shipping_quotes','shipping_events','shipping_notifications']) t,
    unnest(array['anon','authenticated']) r,
    unnest(array['INSERT','UPDATE','DELETE']) p
  where has_table_privilege(r,'public.'||t,p))
union all
select 'manual_rpc_authenticated_only',
  has_function_privilege('authenticated','public.update_manual_shipping(uuid,text,jsonb)','EXECUTE')
  and not has_function_privilege('anon','public.update_manual_shipping(uuid,text,jsonb)','EXECUTE')
union all
select 'checkout_waits_for_shipping',
  pg_get_functiondef('public.create_order_from_cart(bigint,uuid)'::regprocedure) like '%''awaiting_shipping''%'
  and pg_get_functiondef('public.create_order_from_cart(bigint,uuid)'::regprocedure) like '%shipping_value numeric := 0%'
union all
select 'private_offers_wait_for_shipping',
  pg_get_functiondef('public.accept_private_chat_offer(uuid)'::regprocedure) like '%''awaiting_shipping''%'
union all
select 'new_orders_use_quotes', exists(select 1 from information_schema.columns
  where table_schema='public' and table_name='orders' and column_name='shipping_pricing' and column_default like '%quote%')
union all
select 'shipment_trigger_enabled', exists(select 1 from pg_trigger
  where tgrelid='public.orders'::regclass and tgname='initialize_order_shipment' and tgenabled='O');
