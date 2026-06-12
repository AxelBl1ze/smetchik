create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  specialization text,
  logo_path text,
  currency text not null default 'RUB',
  pdf_settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text,
  object_address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  category text not null,
  title text not null,
  unit text not null,
  unit_price numeric(12, 2) not null default 0,
  is_custom boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.estimates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  object_title text not null,
  estimate_date date not null default current_date,
  duration_days integer,
  status text not null default 'draft' check (status in ('draft', 'sent', 'approved', 'declined')),
  total_amount numeric(12, 2) not null default 0,
  pdf_storage_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.estimate_lines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  catalog_item_id uuid references public.catalog_items(id) on delete set null,
  title text not null,
  unit text not null,
  quantity numeric(12, 2) not null default 1,
  unit_price numeric(12, 2) not null default 0,
  line_total numeric(12, 2) not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists clients_user_id_idx on public.clients(user_id);
create index if not exists catalog_items_user_id_idx on public.catalog_items(user_id);
create index if not exists estimates_user_id_idx on public.estimates(user_id);
create index if not exists estimates_client_id_idx on public.estimates(client_id);
create index if not exists estimate_lines_estimate_id_idx on public.estimate_lines(estimate_id);

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists clients_updated_at on public.clients;
create trigger clients_updated_at
before update on public.clients
for each row execute function public.set_updated_at();

drop trigger if exists catalog_items_updated_at on public.catalog_items;
create trigger catalog_items_updated_at
before update on public.catalog_items
for each row execute function public.set_updated_at();

drop trigger if exists estimates_updated_at on public.estimates;
create trigger estimates_updated_at
before update on public.estimates
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.catalog_items enable row level security;
alter table public.estimates enable row level security;
alter table public.estimate_lines enable row level security;

create policy "Users read own profile"
on public.profiles for select
using (id = auth.uid());

create policy "Users insert own profile"
on public.profiles for insert
with check (id = auth.uid());

create policy "Users update own profile"
on public.profiles for update
using (id = auth.uid())
with check (id = auth.uid());

create policy "Users manage own clients"
on public.clients for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users read own and default catalog"
on public.catalog_items for select
using (user_id = auth.uid() or user_id is null);

create policy "Users insert own catalog"
on public.catalog_items for insert
with check (user_id = auth.uid());

create policy "Users update own catalog"
on public.catalog_items for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users delete own catalog"
on public.catalog_items for delete
using (user_id = auth.uid());

create policy "Users manage own estimates"
on public.estimates for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users manage own estimate lines"
on public.estimate_lines for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, currency)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    'RUB'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

insert into public.catalog_items (user_id, category, title, unit, unit_price, is_custom) values
  (null, 'Сантехника', 'Замена смесителя', 'шт', 1500, false),
  (null, 'Сантехника', 'Монтаж унитаза', 'шт', 3200, false),
  (null, 'Сантехника', 'Разводка труб ПП', 'м', 450, false),
  (null, 'Электрика', 'Установка розетки', 'шт', 750, false),
  (null, 'Электрика', 'Прокладка кабеля', 'м', 180, false),
  (null, 'Отделка', 'Демонтаж плитки', 'м²', 350, false),
  (null, 'Отделка', 'Шпатлевка стен', 'м²', 450, false),
  (null, 'Отделка', 'Покраска стен', 'м²', 350, false),
  (null, 'Демонтаж', 'Демонтаж перегородки', 'м²', 800, false),
  (null, 'Монтаж', 'Монтаж гипсокартона', 'м²', 950, false);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('logos', 'logos', true, 5242880, array['image/png', 'image/jpeg', 'image/webp']),
  ('estimate-pdfs', 'estimate-pdfs', true, 10485760, array['application/pdf'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read logos"
on storage.objects for select
using (bucket_id = 'logos');

create policy "Users write own logos"
on storage.objects for insert
with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update own logos"
on storage.objects for update
using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users read estimate pdfs"
on storage.objects for select
using (bucket_id = 'estimate-pdfs');

create policy "Users write own estimate pdfs"
on storage.objects for insert
with check (bucket_id = 'estimate-pdfs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update own estimate pdfs"
on storage.objects for update
using (bucket_id = 'estimate-pdfs' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'estimate-pdfs' and (storage.foldername(name))[1] = auth.uid()::text);
