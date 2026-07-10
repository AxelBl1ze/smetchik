update public.profiles
set subscription_plan = 'pro'
where subscription_plan = 'team';

alter table public.profiles
drop constraint if exists profiles_subscription_plan_check;

alter table public.profiles
add constraint profiles_subscription_plan_check
check (subscription_plan in ('basic', 'pro'));
