create table if not exists public.catalog_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  is_hidden boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, title)
);

create table if not exists public.catalog_hidden_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  title text not null,
  unit text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, category, title, unit)
);

drop trigger if exists catalog_categories_updated_at on public.catalog_categories;
create trigger catalog_categories_updated_at
before update on public.catalog_categories
for each row execute function public.set_updated_at();

alter table public.catalog_categories enable row level security;
alter table public.catalog_hidden_items enable row level security;

create policy "Users manage own catalog categories"
on public.catalog_categories for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users manage own hidden catalog items"
on public.catalog_hidden_items for all
using (user_id = auth.uid())
with check (user_id = auth.uid());
