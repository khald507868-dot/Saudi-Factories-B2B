-- Return one approval stage for correction, without undoing a recorded payment.
begin;
alter table public.shipping_events add column if not exists return_details jsonb;

create or replace function public.return_shipping_stage(
  p_order_id uuid, p_revision integer, p_expected_stage integer, p_reason text
)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare
  o public.orders%rowtype; s public.order_shipments%rowtype;
  owner uuid; admin boolean; paid boolean; stage integer; target integer;
  event_kind text; snapshot jsonb;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 1000 then
    raise exception 'shipping_return_reason_required' using errcode='22023';
  end if;
  -- Same order of row locks as payment confirmation and forward transitions.
  select * into o from public.orders where id=p_order_id for update;
  select f.owner_id into owner from public.factories f where f.id=o.factory_id;
  admin := coalesce(public.is_admin(),false);
  if o.id is null or not coalesce(o.buyer_id=auth.uid() or owner=auth.uid() or admin,false) then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  select * into s from public.order_shipments where order_id=o.id for update;
  if not found or o.status in ('cancelled','payment_failed') or s.status='cancelled' then
    raise exception 'shipping_locked' using errcode='22023';
  end if;
  if p_revision is distinct from s.revision then raise exception 'shipping_stale' using errcode='22023'; end if;
  paid := o.status in ('paid','processing','shipped','completed');
  if paid then
    stage := case when s.status='delivered' then 9
      when s.status in ('collected','departed','arrived') then 8
      when s.pickup_ready_at is not null or s.status='booked' then 7
      when s.production_completed_at is not null then 6 else 5 end;
  else
    if o.status not in ('awaiting_shipping','awaiting_payment') or s.status not in
      ('awaiting_details','awaiting_quote','quoted','booking_requested') then
      raise exception 'shipping_locked' using errcode='22023';
    end if;
    stage := case when s.buyer_confirmed_at is null then 1
      when s.factory_confirmed_at is null then 2
      when exists(select 1 from public.shipping_quotes q where q.id=s.current_quote_id
        and q.order_id=o.id and (q.accepted_at is not null or q.expires_at>clock_timestamp())) then 4 else 3 end;
  end if;
  if p_expected_stage is distinct from stage then raise exception 'shipping_stale' using errcode='22023'; end if;
  if stage=1 then raise exception 'shipping_locked' using errcode='22023'; end if;
  -- Production cannot return across the confirmed-payment boundary.
  if stage=5 then raise exception 'shipping_return_payment_locked' using errcode='22023'; end if;
  if paid and not admin and not coalesce(owner=auth.uid() and
    (stage=6 or (stage=7 and s.status='booking_requested')),false) then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  target := stage-1;
  snapshot := jsonb_build_object('from_stage',stage,'to_stage',target,'shipment',to_jsonb(s),
    'order_status',o.status,'order_total',o.total,'order_shipping',o.shipping);
  if not paid then
    -- Keep entered data and quote history, but require new approvals/pricing.
    if target=1 then s.buyer_confirmed_at := null; end if;
    if target<=2 then s.factory_confirmed_at := null; end if;
    s.current_quote_id := null;
    s.status := case when target=3 then 'awaiting_quote' else 'awaiting_details' end;
    update public.orders set status='awaiting_shipping',shipping=0,
      total=subtotal+payment_fee+vat_amount,updated_at=clock_timestamp() where id=o.id;
  elsif target=5 then
    s.production_completed_at := null;
    update public.orders set status='processing',updated_at=clock_timestamp() where id=o.id;
  elsif target=6 then
    s.pickup_ready_at := null; s.booking_reference := null; s.pickup_at := null;
    s.status := 'booking_requested';
    update public.orders set status='processing',updated_at=clock_timestamp() where id=o.id;
  elsif target=7 then
    s.status := 'booked';
    update public.orders set status='processing',updated_at=clock_timestamp() where id=o.id;
  elsif target=8 then
    s.status := 'arrived';
    update public.orders set status='shipped',updated_at=clock_timestamp() where id=o.id;
  end if;
  update public.order_shipments set status=s.status,buyer_confirmed_at=s.buyer_confirmed_at,
    factory_confirmed_at=s.factory_confirmed_at,current_quote_id=s.current_quote_id,
    production_completed_at=s.production_completed_at,pickup_ready_at=s.pickup_ready_at,
    booking_reference=s.booking_reference,pickup_at=s.pickup_at,
    revision=revision+1,updated_at=clock_timestamp() where order_id=o.id returning * into s;
  event_kind := 'returned_to_stage_'||target;
  insert into public.shipping_events(order_id,kind,note,actor_id,return_details)
    values(o.id,event_kind,btrim(p_reason),auth.uid(),snapshot);
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,event_kind from public.profiles
    where (id=o.buyer_id or id=owner or is_admin=true) and id<>auth.uid();
  return s;
end $$;
revoke all on function public.return_shipping_stage(uuid,integer,integer,text) from public,anon;
grant execute on function public.return_shipping_stage(uuid,integer,integer,text) to authenticated;
notify pgrst, 'reload schema';
commit;
