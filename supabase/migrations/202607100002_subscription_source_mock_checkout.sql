alter table public.profiles
add column if not exists subscription_source text not null default 'manual';

update public.profiles
set subscription_source = 'manual'
where subscription_source is null;

alter table public.profiles
drop constraint if exists profiles_subscription_source_check;

alter table public.profiles
add constraint profiles_subscription_source_check
check (subscription_source in ('manual', 'mock', 'web', 'google_play', 'apple'));
