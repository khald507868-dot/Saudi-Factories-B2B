-- Image banners no longer require a title. Keep legacy titles and RLS intact.
begin;
alter table public.home_promotions drop constraint if exists home_promotions_title_check;
alter table public.home_promotions add constraint home_promotions_title_check
  check (char_length(btrim(title)) <= 120);
alter table public.home_promotions alter column title set default '';
notify pgrst, 'reload schema';
commit;
