-- Remove broad profile-row access. Conversation peer metadata is served by
-- get_conversation_peers(), which returns only the required public fields.
drop policy if exists profiles_select_conversation_party on public.profiles;
