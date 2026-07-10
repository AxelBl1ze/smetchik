alter table public.estimates
drop constraint if exists estimates_status_check;

update public.estimates
set status = 'in_progress'
where status = 'approved';

alter table public.estimates
add constraint estimates_status_check
check (
  status in (
    'draft',
    'sent',
    'accepted',
    'in_progress',
    'completed',
    'declined'
  )
);

alter table public.profiles
add column if not exists subscription_plan text not null default 'basic',
add column if not exists subscription_status text not null default 'active',
add column if not exists subscription_renews_at timestamptz;

alter table public.profiles
drop constraint if exists profiles_subscription_plan_check;

alter table public.profiles
add constraint profiles_subscription_plan_check
check (subscription_plan in ('basic', 'pro', 'team'));

alter table public.profiles
drop constraint if exists profiles_subscription_status_check;

alter table public.profiles
add constraint profiles_subscription_status_check
check (subscription_status in ('active', 'trialing', 'past_due', 'canceled'));
