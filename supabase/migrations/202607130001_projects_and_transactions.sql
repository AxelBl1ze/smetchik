create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  object_address text,
  customer_name text,
  planned_revenue numeric(12, 2) not null default 0 check (planned_revenue >= 0),
  start_date date not null default current_date,
  target_date date,
  status text not null default 'planning'
    check (status in ('planning', 'active', 'completed', 'sold')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  transaction_type text not null
    check (transaction_type in ('income', 'expense')),
  category text not null,
  title text not null,
  amount numeric(12, 2) not null check (amount >= 0),
  quantity numeric(12, 2),
  unit text,
  transaction_date date not null default current_date,
  counterparty text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists projects_user_status_idx
on public.projects(user_id, status, updated_at desc);

create index if not exists project_transactions_project_date_idx
on public.project_transactions(project_id, transaction_date desc);

alter table public.projects enable row level security;
alter table public.project_transactions enable row level security;

create policy "Users manage own projects"
on public.projects for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users manage own project transactions"
on public.project_transactions for all to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.projects
    where projects.id = project_id and projects.user_id = auth.uid()
  )
);

drop trigger if exists projects_updated_at on public.projects;
create trigger projects_updated_at
before update on public.projects
for each row execute function public.set_updated_at();

drop trigger if exists project_transactions_updated_at on public.project_transactions;
create trigger project_transactions_updated_at
before update on public.project_transactions
for each row execute function public.set_updated_at();
