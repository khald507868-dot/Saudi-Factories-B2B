begin;

-- Read server-owned confirmation and approval state, never user_metadata/JWT
-- metadata supplied by the registering user. Pending owners can read their
-- application through the existing policies, but cannot perform mutations.
create or replace function public.account_can_write()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from auth.users u join public.profiles p on p.id = u.id
    where u.id = auth.uid() and u.email_confirmed_at is not null
      and (p.is_admin is true or p.account_type = 'individual'
        or (p.account_type = 'factory' and exists (
          select 1 from public.factories f
          where f.owner_id = u.id and f.status = 'approved'
        )))
  );
$$;
revoke all on function public.account_can_write() from public, anon;
grant execute on function public.account_can_write() to authenticated, service_role;

create or replace function public.require_approved_account_write()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  -- Backend registration/admin maintenance has no end-user JWT or uses the
  -- service role. SECURITY DEFINER RPCs retain the caller's JWT and are checked.
  if auth.uid() is not null and coalesce(auth.role(), '') <> 'service_role'
     and not public.account_can_write() then
    raise exception 'Email confirmation and factory approval are required'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.require_approved_account_write() from public, anon, authenticated;

-- Guard existing application tables, including writes inside SECURITY DEFINER
-- commerce/content RPCs, without replacing their ownership/RLS rules.
do $$
declare item record;
begin
  for item in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')
  loop
    execute format('drop trigger if exists account_approval_write_guard on public.%I', item.relname);
    execute format('create trigger account_approval_write_guard before insert or update or delete on public.%I for each row execute function public.require_approved_account_write()', item.relname);
  end loop;
end $$;

-- Storage uploads must follow the same rule. Existing bucket ownership and
-- admin-only advertising policies continue to apply.
drop policy if exists account_approval_storage_insert on storage.objects;
create policy account_approval_storage_insert on storage.objects as restrictive
  for insert to authenticated with check ((select public.account_can_write()));
drop policy if exists account_approval_storage_update on storage.objects;
create policy account_approval_storage_update on storage.objects as restrictive
  for update to authenticated using ((select public.account_can_write())) with check ((select public.account_can_write()));
drop policy if exists account_approval_storage_delete on storage.objects;
create policy account_approval_storage_delete on storage.objects as restrictive
  for delete to authenticated using ((select public.account_can_write()));

notify pgrst, 'reload schema';
commit;
