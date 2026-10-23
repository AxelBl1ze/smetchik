begin;

create table public.project_rooms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  data jsonb not null check (
    jsonb_typeof(data) = 'object' and octet_length(data::text) <= 262144
    and data ?& array['name', 'width', 'depth', 'height', 'walls', 'openings', 'finishes']
    and jsonb_typeof(data->'width') = 'number'
    and jsonb_typeof(data->'depth') = 'number'
    and jsonb_typeof(data->'height') = 'number'
    and jsonb_typeof(data->'name') = 'string'
    and length(btrim(data->>'name')) between 1 and 120
    and jsonb_typeof(data->'walls') = 'array'
    and jsonb_array_length(data->'walls') between 3 and 64
    and jsonb_typeof(data->'openings') = 'array'
    and jsonb_array_length(data->'openings') <= 64
    and jsonb_typeof(data->'finishes') = 'array'
    and jsonb_array_length(data->'finishes') <= 60
    and (data->>'width')::numeric between 0.1 and 200
    and (data->>'depth')::numeric between 0.1 and 200
    and (data->>'height')::numeric between 0.1 and 200
  ),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index project_rooms_project_idx on public.project_rooms(project_id, created_at);
alter table public.project_rooms enable row level security;
grant select, insert, update, delete on public.project_rooms to authenticated;
create policy "Users manage rooms of own projects"
on public.project_rooms for all to authenticated
using (user_id = auth.uid() and exists (
  select 1 from public.projects p where p.id = project_id and p.user_id = auth.uid()
))
with check (user_id = auth.uid() and exists (
  select 1 from public.projects p where p.id = project_id and p.user_id = auth.uid()
));

create function public.project_room_revision()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id or new.project_id <> old.project_id or new.id <> old.id then
      raise exception 'Нельзя перенести помещение в другой объект';
    end if;
    new.revision := old.revision + 1;
    new.created_at := old.created_at;
  else
    new.revision := 1;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger project_rooms_revision before insert or update
on public.project_rooms for each row execute function public.project_room_revision();

commit;
