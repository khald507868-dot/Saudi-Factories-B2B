-- Only the Edge Function (service_role) may inventory another user's media.
-- Clients cannot call this helper, or select a target account to delete.
create or replace function public.account_deletion_media(target_user uuid)
returns table(bucket_id text, name text)
language plpgsql security definer set search_path = ''
as $fn$
begin
  if exists (
    select 1 from public.orders o
    where o.buyer_id = target_user
       or o.factory_id in (select f.id from public.factories f where f.owner_id = target_user)
  ) then
    raise exception 'account_has_orders' using errcode = 'P0001';
  end if;
  return query
    select o.bucket_id::text, o.name::text from storage.objects o
    where coalesce(o.owner_id, o.owner::text) = target_user::text
    order by o.bucket_id, o.name limit 100;
end;
$fn$;
revoke all on function public.account_deletion_media(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_media(uuid) to service_role;
