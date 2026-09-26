-- Export preferences travel with the existing destination and quote snapshot.
-- Older clients and historical destinations without preferences remain valid.
begin;
create or replace function public.validate_shipping_export_preferences()
returns trigger language plpgsql set search_path = '' as $$
declare p jsonb; k text; mode text; service text; route text; term text;
begin
  if tg_op = 'UPDATE' then
    if new.destination is not distinct from old.destination
       and new.delivery_type is not distinct from old.delivery_type then return new; end if;
  end if;
  if new.destination is null or not (new.destination ? 'export_preferences') then return new; end if;
  p := new.destination->'export_preferences';
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  if p->'version' is distinct from '1'::jsonb or p->>'incoterms_version' is distinct from '2020'
     or new.destination->>'scope' is distinct from 'international' then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  foreach k in array array['transport_mode','delivery_route','incoterm','named_place','incoterms_version'] loop
    if jsonb_typeof(p->k) is distinct from 'string' or length(btrim(p->>k)) not between 1 and 200 then
      raise exception 'shipping_invalid_export_preferences';
    end if;
  end loop;
  mode := p->>'transport_mode'; service := p->>'sea_service';
  route := p->>'delivery_route'; term := p->>'incoterm';
  if mode not in ('sea','air','road','rail','express','multimodal')
     or route not in ('door_to_door','door_to_port','port_to_port','port_to_door')
     or term not in ('EXW','FCA','FOB','CFR','CIF','CPT','CIP','DAP','DPU','DDP')
     or (mode <> 'sea' and term in ('FOB','CFR','CIF')) then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  if mode = 'sea' then
    if service is null or service not in ('fcl','lcl','break_bulk','ro_ro','bulk') then
      raise exception 'shipping_invalid_export_preferences';
    end if;
  elsif service is not null then raise exception 'shipping_invalid_export_preferences'; end if;
  if service = 'fcl' then
    if coalesce(p->>'container_type','') not in ('20ft','40ft','40ft_hc')
       or jsonb_typeof(p->'container_count') is distinct from 'number' then
      raise exception 'shipping_invalid_export_preferences';
    end if;
    if (p->>'container_count')::numeric not between 1 and 1000
       or trunc((p->>'container_count')::numeric) <> (p->>'container_count')::numeric then
      raise exception 'shipping_invalid_export_preferences';
    end if;
  elsif p->>'container_type' is not null or p->>'container_count' is not null then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  if route in ('port_to_port','port_to_door') then
    if jsonb_typeof(p->'origin_terminal') is distinct from 'string'
       or length(btrim(p->>'origin_terminal')) not between 1 and 200 then
      raise exception 'shipping_invalid_export_preferences';
    end if;
  elsif p->>'origin_terminal' is not null then raise exception 'shipping_invalid_export_preferences'; end if;
  if new.delivery_type is distinct from (case when route in ('door_to_port','port_to_port') then 'port' else 'door' end) then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  if new.delivery_type = 'port' and (jsonb_typeof(new.destination->'port') is distinct from 'string'
     or length(btrim(new.destination->>'port')) not between 1 and 200) then
    raise exception 'shipping_invalid_export_preferences';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_shipping_export_preferences() from public, anon, authenticated;
drop trigger if exists shipping_export_preferences_check on public.order_shipments;
create trigger shipping_export_preferences_check before insert or update of destination, delivery_type
  on public.order_shipments for each row execute function public.validate_shipping_export_preferences();
commit;
