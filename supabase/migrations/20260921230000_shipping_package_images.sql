-- صور تغليف خاصة بالطلب، مع منع استبدال ملفات الصور بعد رفعها.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('shipment-images','shipment-images',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.shipping_image_access(p_path text,p_write boolean)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'
  and exists(select 1 from public.orders o join public.factories f on f.id=o.factory_id
    join public.order_shipments s on s.order_id=o.id where o.id::text=split_part(p_path,'/',1)
    and case when p_write then
      f.owner_id=auth.uid() and public.account_can_write() and o.status='awaiting_shipping'
      and s.status in ('awaiting_details','awaiting_quote','quoted') and s.buyer_confirmed_at is not null
    else
      f.owner_id=auth.uid() or public.is_admin() or (o.buyer_id=auth.uid() and (
        s.packing @> jsonb_build_object('packages',jsonb_build_array(jsonb_build_object('photos',jsonb_build_array(p_path))))
        or exists(select 1 from public.shipping_quotes q where q.order_id=o.id
          and q.packing_snapshot @> jsonb_build_object('packages',jsonb_build_array(jsonb_build_object('photos',jsonb_build_array(p_path)))))
      )) end);
$$;
revoke all on function public.shipping_image_access(text,boolean) from public,anon;
grant execute on function public.shipping_image_access(text,boolean) to authenticated;

drop policy if exists shipment_images_read on storage.objects;
create policy shipment_images_read on storage.objects for select to authenticated
  using(bucket_id='shipment-images' and public.shipping_image_access(name,false));
drop policy if exists shipment_images_insert on storage.objects;
create policy shipment_images_insert on storage.objects for insert to authenticated
  with check(bucket_id='shipment-images' and public.shipping_image_access(name,true));
-- لا تسمح أي سياسة تخص حاوية أخرى بتجاوز عزل هذه الصور.
drop policy if exists shipment_images_read_guard on storage.objects;
create policy shipment_images_read_guard on storage.objects as restrictive for select to authenticated
  using(bucket_id<>'shipment-images' or public.shipping_image_access(name,false));
drop policy if exists shipment_images_insert_guard on storage.objects;
create policy shipment_images_insert_guard on storage.objects as restrictive for insert to authenticated
  with check(bucket_id<>'shipment-images' or public.shipping_image_access(name,true));
drop policy if exists shipment_images_immutable on storage.objects;
create policy shipment_images_immutable on storage.objects as restrictive for update to authenticated
  using(bucket_id<>'shipment-images') with check(bucket_id<>'shipment-images');
drop policy if exists shipment_images_preserve on storage.objects;
create policy shipment_images_preserve on storage.objects as restrictive for delete to authenticated
  using(bucket_id<>'shipment-images');

create or replace function public.validate_shipping_package_images()
returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb; photo jsonb; path text; total integer:=0;
begin
  if tg_op='UPDATE' and new.packing is not distinct from old.packing then return new; end if;
  for item in select value from jsonb_array_elements(new.packing->'packages') loop
    if item ? 'photos' then
      if jsonb_typeof(item->'photos') is distinct from 'array' then
        raise exception 'shipping_invalid_images' using errcode='22023';
      end if;
      if jsonb_array_length(item->'photos')>5 then raise exception 'shipping_image_limit' using errcode='22023'; end if;
      total:=total+jsonb_array_length(item->'photos');
      if total>20 then raise exception 'shipping_image_limit' using errcode='22023'; end if;
      for photo in select value from jsonb_array_elements(item->'photos') loop
        path:=photo#>>'{}';
        if jsonb_typeof(photo)<>'string' or split_part(path,'/',1)<>new.order_id::text
          or path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
          or not exists(select 1 from storage.objects where bucket_id='shipment-images' and name=path
            and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')) then
          raise exception 'shipping_invalid_images' using errcode='22023';
        end if;
      end loop;
    end if;
  end loop;
  return new;
end $$;
revoke all on function public.validate_shipping_package_images() from public,anon,authenticated;
drop trigger if exists validate_shipping_package_images on public.order_shipments;
create trigger validate_shipping_package_images before insert or update on public.order_shipments
  for each row execute function public.validate_shipping_package_images();
notify pgrst, 'reload schema';
commit;
