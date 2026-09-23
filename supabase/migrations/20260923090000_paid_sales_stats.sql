-- Count sales only after payment confirmation, including later fulfilment states.
-- Run in Supabase SQL Editor. Safe to rerun; no order or payment data is changed.
begin;

create or replace function public.get_public_stats()
returns table (
  factories_count bigint,
  products_count bigint,
  units_sold numeric,
  revenue numeric
)
language sql
security definer
set search_path = public
stable
as $fn$
  with paid_orders as (
    select o.id, o.total
      from public.orders o
     where o.status in ('paid', 'processing', 'shipped', 'completed')
  )
  select
    (select count(*) from public.factories where status = 'approved'),
    (select count(*) from public.products p
       join public.factories f on f.id = p.factory_id
      where f.status = 'approved'),
    coalesce((
      select sum(oi.quantity)
        from public.order_items oi
        join paid_orders o on o.id = oi.order_id
    ), 0),
    coalesce((select sum(o.total) from paid_orders o), 0);
$fn$;

-- Keep the public aggregate available without exposing individual orders.
revoke all on function public.get_public_stats() from public;
grant execute on function public.get_public_stats() to anon, authenticated;

commit;

select * from public.get_public_stats();
