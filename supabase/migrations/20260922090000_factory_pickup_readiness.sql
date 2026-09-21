-- تأكيد المصنع للجاهزية بعد الدفع، وإشعار الإدارة لتنسيق استلام شركة الشحن.
begin;
alter table public.order_shipments add column if not exists pickup_ready_at timestamptz;

create or replace function public.confirm_shipping_pickup_ready(p_order_id uuid,p_revision integer)
returns public.order_shipments language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype; s public.order_shipments%rowtype;
begin
  if auth.uid() is null or not public.account_can_write() then
    raise exception 'shipping_access_denied' using errcode='42501';
  end if;
  select ord.* into o from public.orders ord join public.factories f on f.id=ord.factory_id
    where ord.id=p_order_id and f.owner_id=auth.uid() for update of ord;
  if not found then raise exception 'shipping_access_denied' using errcode='42501'; end if;
  select * into s from public.order_shipments where order_id=o.id for update;
  if not found or o.status in ('cancelled','payment_failed') then
    raise exception 'shipping_locked' using errcode='22023';
  end if;
  if o.status not in ('paid','processing','shipped','completed') then
    raise exception 'shipping_payment_required' using errcode='22023';
  end if;
  -- إعادة الطلب بعد فقد الرد لا تكرر الإشعار أو وقت التأكيد.
  if s.pickup_ready_at is not null then return s; end if;
  if s.status<>'booking_requested' or s.buyer_confirmed_at is null or s.factory_confirmed_at is null
    or not exists(select 1 from public.shipping_quotes q where q.id=s.current_quote_id and q.order_id=o.id and q.accepted_at is not null) then
    raise exception 'shipping_locked' using errcode='22023';
  end if;
  if p_revision is distinct from s.revision then raise exception 'shipping_stale' using errcode='22023'; end if;
  update public.order_shipments set pickup_ready_at=clock_timestamp(),revision=revision+1,updated_at=clock_timestamp()
    where order_id=o.id returning * into s;
  insert into public.shipping_events(order_id,kind,note,actor_id) values(o.id,'pickup_ready','',auth.uid());
  insert into public.shipping_notifications(recipient_id,order_id,kind)
    select id,o.id,'pickup_ready' from public.profiles where is_admin=true;
  return s;
end $$;
revoke all on function public.confirm_shipping_pickup_ready(uuid,integer) from public,anon;
grant execute on function public.confirm_shipping_pickup_ready(uuid,integer) to authenticated;

-- يمنع تجاوز التأكيد عبر دالة الحجز الحالية أو أي مسار تحديث آخر.
create or replace function public.require_shipping_pickup_ready()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.status='booked' and old.status<>'booked' and new.pickup_ready_at is null then
    raise exception 'shipping_pickup_ready_required' using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.require_shipping_pickup_ready() from public,anon,authenticated;
drop trigger if exists require_shipping_pickup_ready on public.order_shipments;
create trigger require_shipping_pickup_ready before update on public.order_shipments
  for each row execute function public.require_shipping_pickup_ready();

-- يُبلّغ المصنع بالخطوة المطلوبة حتى لو أكدت الإدارة استلام الدفع.
create or replace function public.notify_factory_pickup_readiness()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='paid' and old.status is distinct from new.status and exists(
    select 1 from public.order_shipments s where s.order_id=new.id and s.status='booking_requested' and s.pickup_ready_at is null
  ) then
    insert into public.shipping_notifications(recipient_id,order_id,kind)
      select owner_id,new.id,'pickup_ready_needed' from public.factories where id=new.factory_id;
  end if;
  return new;
end $$;
revoke all on function public.notify_factory_pickup_readiness() from public,anon,authenticated;
drop trigger if exists notify_factory_pickup_readiness on public.orders;
create trigger notify_factory_pickup_readiness after update on public.orders
  for each row execute function public.notify_factory_pickup_readiness();
notify pgrst, 'reload schema';
commit;
