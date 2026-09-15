begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('factory-certificates','factory-certificates',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create table if not exists public.factory_certificates (
  id uuid primary key default gen_random_uuid(),
  factory_id bigint not null references public.factories(id) on delete cascade,
  image_path text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists factory_certificates_factory_idx on public.factory_certificates(factory_id,created_at,id);
alter table public.factory_certificates enable row level security;
revoke all on public.factory_certificates from public,anon,authenticated;
grant select on public.factory_certificates to anon,authenticated;
grant insert,delete on public.factory_certificates to authenticated;
drop policy if exists factory_certificates_read on public.factory_certificates;
create policy factory_certificates_read on public.factory_certificates for select to anon,authenticated using(
  exists(select 1 from public.factories f where f.id=factory_id and (f.status='approved' or f.owner_id=auth.uid()))
);
drop policy if exists factory_certificates_add on public.factory_certificates;
create policy factory_certificates_add on public.factory_certificates for insert to authenticated with check(
  public.account_can_write() and exists(select 1 from public.factories f where f.id=factory_id and f.owner_id=auth.uid() and f.status='approved')
);
drop policy if exists factory_certificates_delete on public.factory_certificates;
create policy factory_certificates_delete on public.factory_certificates for delete to authenticated using(
  public.account_can_write() and exists(select 1 from public.factories f where f.id=factory_id and f.owner_id=auth.uid() and f.status='approved')
);

create or replace function public.validate_factory_certificate()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.account_can_write() or not exists(
    select 1 from public.factories f where f.id=new.factory_id and f.owner_id=auth.uid() and f.status='approved'
  ) then raise exception 'certificate_access_denied' using errcode='42501'; end if;
  if new.image_path !~ ('^' || auth.uid()::text || '/certificates/' || new.factory_id::text || '/[A-Za-z0-9-]+\.(jpg|png|webp)$')
    or not exists(select 1 from storage.objects o where o.bucket_id='factory-certificates' and o.name=new.image_path
      and o.metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')) then
    raise exception 'certificate_image_required' using errcode='22023';
  end if;
  new.created_at:=clock_timestamp();
  return new;
end;
$$;
revoke all on function public.validate_factory_certificate() from public,anon,authenticated;
drop trigger if exists factory_certificate_image_guard on public.factory_certificates;
create trigger factory_certificate_image_guard before insert on public.factory_certificates for each row execute function public.validate_factory_certificate();
drop trigger if exists account_approval_write_guard on public.factory_certificates;
create trigger account_approval_write_guard before insert or update or delete on public.factory_certificates for each row execute function public.require_approved_account_write();

drop policy if exists factory_certificates_storage_read on storage.objects;
create policy factory_certificates_storage_read on storage.objects for select to authenticated using(
  bucket_id='factory-certificates' and split_part(name,'/',1)=auth.uid()::text
);
drop policy if exists factory_certificates_storage_add on storage.objects;
create policy factory_certificates_storage_add on storage.objects for insert to authenticated with check(
  bucket_id='factory-certificates' and split_part(name,'/',1)=auth.uid()::text and split_part(name,'/',2)='certificates'
  and public.account_can_write() and exists(select 1 from public.factories f where f.id::text=split_part(name,'/',3) and f.owner_id=auth.uid() and f.status='approved')
);
drop policy if exists factory_certificates_storage_delete on storage.objects;
create policy factory_certificates_storage_delete on storage.objects for delete to authenticated using(
  bucket_id='factory-certificates' and split_part(name,'/',1)=auth.uid()::text and public.account_can_write()
);
notify pgrst,'reload schema';
commit;
