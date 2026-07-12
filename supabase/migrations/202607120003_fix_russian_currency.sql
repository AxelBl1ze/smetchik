-- The MVP is for the Russian market. Existing profiles and future profile
-- saves use the Russian ruble even though the field remains for compatibility.
update public.profiles
set currency = 'RUB'
where currency is distinct from 'RUB';
