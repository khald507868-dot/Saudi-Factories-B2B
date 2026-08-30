-- Fast conversation summaries and durable per-conversation unread counts.

alter table public.messages
  add column if not exists read_at timestamptz;

create index if not exists messages_unread_conversation_idx
  on public.messages(conversation_id, sender_id)
  where read_at is null;

create index if not exists conversations_individual_recent_idx
  on public.conversations(individual_id, last_message_at desc);

drop policy if exists messages_update_party on public.messages;
create policy messages_update_party on public.messages
  for update to authenticated
  using (
    public.in_conversation(conversation_id)
    and sender_id <> auth.uid()
  )
  with check (
    public.in_conversation(conversation_id)
    and sender_id <> auth.uid()
  );

create or replace function public.get_conversation_summaries()
returns table (
  conversation_id bigint,
  factory_id bigint,
  individual_id uuid,
  peer_name text,
  peer_avatar text,
  peer_role text,
  last_message_body text,
  last_message_type text,
  last_message_created_at timestamptz,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  unread_count bigint
)
language sql
security definer
set search_path = public
stable
as $fn$
  select
    c.id,
    c.factory_id,
    c.individual_id,
    case when c.individual_id = auth.uid()
      then coalesce(f.name, '')
      else coalesce(p.full_name, '')
    end,
    case when c.individual_id = auth.uid()
      then coalesce(f.logo, '')
      else coalesce(p.company_image, '')
    end,
    case when c.individual_id = auth.uid()
      then 'factory'::text
      else 'individual'::text
    end,
    coalesce(lm.body, ''),
    coalesce(lm.attachment_type, ''),
    lm.created_at,
    lm.sender_id,
    c.last_message_at,
    (
      select count(*)
        from public.messages unread
       where unread.conversation_id = c.id
         and unread.sender_id <> auth.uid()
         and unread.read_at is null
    )
  from public.conversations c
  join public.factories f on f.id = c.factory_id
  join public.profiles p on p.id = c.individual_id
  left join lateral (
    select m.body, m.attachment_type, m.created_at, m.sender_id
      from public.messages m
     where m.conversation_id = c.id
     order by m.created_at desc, m.id desc
     limit 1
  ) lm on true
  where c.individual_id = auth.uid()
     or f.owner_id = auth.uid()
  order by coalesce(lm.created_at, c.created_at) desc, c.id desc;
$fn$;

revoke all on function public.get_conversation_summaries() from public;
grant execute on function public.get_conversation_summaries() to authenticated;

create or replace function public.mark_conversation_read(p_conversation_id bigint)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  affected integer := 0;
begin
  if auth.uid() is null or not public.in_conversation(p_conversation_id) then
    raise exception 'Conversation access denied' using errcode = '42501';
  end if;

  update public.messages
     set read_at = now()
   where conversation_id = p_conversation_id
     and sender_id <> auth.uid()
     and read_at is null;

  get diagnostics affected = row_count;
  return affected;
end;
$fn$;

revoke all on function public.mark_conversation_read(bigint) from public;
grant execute on function public.mark_conversation_read(bigint) to authenticated;
