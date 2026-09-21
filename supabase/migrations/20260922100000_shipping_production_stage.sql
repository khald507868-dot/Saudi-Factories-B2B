-- الإنتاج بين الدفع وتأكيد جاهزية الشحنة، دون تغيير تواريخ الطلبات السابقة.
begin;
alter table public.order_shipments add column if not exists production_started_at timestamptz,
  add column if not exists production_completed_at timestamptz;

create or replace function public.update_shipping_production(p_order_id uuid,p_revision integer,p_action text)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; s public.order_shipments%rowtype; event_kind text;
begin
  if auth.uid() is null or not public.account_can_write() then raise exception 'shipping_access_denied' using errcode='42501'; end if;
  if p_action is null or p_action not in ('start','complete') then raise exception 'shipping_invalid_action' using errcode='22023'; end if;
  select ord.* into o from public.orders ord join public.factories f on f.id=ord.factory_id
    where ord.id=p_order_id and f.owner_id=auth.uid() for update of ord;
  if not found then raise exception 'shipping_access_denied' using errcode='42501'; end if;
  select * into s from public.order_shipments where order_id=o.id for update;
  if not found or o.status in ('cancelled','payment_failed') then raise exception 'shipping_locked' using errcode='22023'; end if;
  if o.status not in ('paid','processing','shipped','completed') then raise exception 'shipping_payment_required' using errcode='22023'; end if;
  if (p_action='start' and s.production_started_at is not null) or (p_action='complete' and s.production_completed_at is not null) then return s; end if;
  if s.status<>'booking_requested' or s.pickup_ready_at is not null or s.buyer_confirmed_at is null or s.factory_confirmed_at is null
    or not exists(select 1 from public.shipping_quotes q where q.id=s.current_quote_id and q.order_id=o.id and q.accepted_at is not null) then
    raise exception 'shipping_locked' using errcode='22023';
  end if;
  if p_revision is distinct from s.revision then raise exception 'shipping_stale' using errcode='22023'; end if;
  if p_action='start' then
    update public.order_shipments set production_started_at=clock_timestamp(),revision=revision+1,updated_at=clock_timestamp()
      where order_id=o.id returning * into s;
    update public.orders set status='processing',updated_at=clock_timestamp() where id=o.id;
    event_kind:='production_started';
  else
    if s.production_started_at is null then raise exception 'shipping_production_start_required' using errcode='22023'; end if;
    update public.order_shipments set production_completed_at=clock_timestamp(),revision=revision+1,updated_at=clock_timestamp()
      where order_id=o.id returning * into s;
    event_kind:='production_completed';
  end if;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,event_kind,'',auth.uid());
  insert into public.shipping_notifications(recipient_id,order_id,kind) values(o.buyer_id,o.id,event_kind);
  return s;
end $$;
revoke all on function public.update_shipping_production(uuid,integer,text) from public,anon;
grant execute on function public.update_shipping_production(uuid,integer,text) to authenticated;

create or replace function public.require_shipping_production_completed()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.pickup_ready_at is not null and old.pickup_ready_at is null and new.production_completed_at is null then
    raise exception 'shipping_production_required' using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.require_shipping_production_completed() from public,anon,authenticated;
drop trigger if exists require_shipping_production_completed on public.order_shipments;
create trigger require_shipping_production_completed before update on public.order_shipments
  for each row execute function public.require_shipping_production_completed();

create or replace function public.notify_factory_pickup_readiness()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='paid' and old.status is distinct from new.status and exists(
    select 1 from public.order_shipments s where s.order_id=new.id and s.status='booking_requested' and s.pickup_ready_at is null
  ) then
    insert into public.shipping_notifications(recipient_id,order_id,kind)
      select owner_id,new.id,'production_needed' from public.factories where id=new.factory_id;
  end if;
  return new;
end $$;
revoke all on function public.notify_factory_pickup_readiness() from public,anon,authenticated;
notify pgrst, 'reload schema';
commit;
