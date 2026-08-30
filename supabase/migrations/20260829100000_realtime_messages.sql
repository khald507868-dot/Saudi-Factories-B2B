-- Complete the server side of the web/app messaging flow.

-- The authenticated clients need explicit access in installations that do not
-- inherit Supabase's default table grants.
grant select, insert on public.conversations to authenticated;
grant select, insert, update on public.messages to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Only individual accounts may start a conversation, and only with an
-- approved factory. Factory owners can still read and reply to conversations
-- opened by their customers through the existing select/message policies.
drop policy if exists conversations_insert_individual on public.conversations;
create policy conversations_insert_individual on public.conversations
  for insert to authenticated
  with check (
    individual_id = auth.uid()
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and p.account_type = 'individual'
    )
    and exists (
      select 1 from public.factories f
       where f.id = factory_id
         and f.status = 'approved'
    )
  );

-- Keep the conversation list correctly ordered whenever either party sends a
-- message. The trigger runs on the server, so every browser sees the same time.
create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.conversations
     set last_message_at = greatest(last_message_at, new.created_at)
   where id = new.conversation_id;
  return new;
end;
$fn$;

drop trigger if exists messages_touch_conversation on public.messages;
create trigger messages_touch_conversation
  after insert on public.messages
  for each row execute function public.touch_conversation_from_message();

revoke all on function public.touch_conversation_from_message() from public;

-- Return only the counterpart fields the chat header needs. This avoids
-- opening the entire profiles row (email, phone, etc.) to the other party.
create or replace function public.get_conversation_peers()
returns table (
  conversation_id bigint,
  peer_name text,
  peer_avatar text,
  peer_role text
)
language sql
security definer
set search_path = public
stable
as $fn$
  select
    c.id,
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
    end
  from public.conversations c
  join public.factories f on f.id = c.factory_id
  join public.profiles p on p.id = c.individual_id
  where c.individual_id = auth.uid()
     or f.owner_id = auth.uid();
$fn$;

revoke all on function public.get_conversation_peers() from public;
grant execute on function public.get_conversation_peers() to authenticated;
