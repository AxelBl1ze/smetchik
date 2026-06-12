create table if not exists public.phone_auth_accounts (
  phone text primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists phone_auth_accounts_updated_at on public.phone_auth_accounts;
create trigger phone_auth_accounts_updated_at
before update on public.phone_auth_accounts
for each row execute function public.set_updated_at();

alter table public.phone_auth_accounts enable row level security;
