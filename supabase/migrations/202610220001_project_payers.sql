begin;

alter table public.project_transactions add column if not exists payer_name text;

create table public.project_payers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  created_at timestamptz not null default now()
);
create unique index project_payers_project_name_idx
on public.project_payers(project_id, lower(name));

alter table public.project_payers enable row level security;
grant select, insert, update, delete on public.project_payers to authenticated;
create policy "Users manage own project payers"
on public.project_payers for all to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid() and exists (
    select 1 from public.projects p
    where p.id = project_id and p.user_id = auth.uid()
  )
);

-- У поступлений контрагент был плательщиком. Поставщиков расходов не переносим.
update public.project_transactions
set payer_name = btrim(regexp_replace(counterparty, '\s+', ' ', 'g'))
where transaction_type = 'income' and payer_name is null
  and nullif(btrim(counterparty), '') is not null;

insert into public.project_payers(user_id, project_id, name)
select distinct on (project_id, lower(payer_name)) user_id, project_id, payer_name
from public.project_transactions
where nullif(btrim(payer_name), '') is not null
order by project_id, lower(payer_name), created_at
on conflict (project_id, lower(name)) do nothing;

create function public.remember_project_payer()
returns trigger language plpgsql set search_path = public as $$
declare canonical_name text;
begin
  new.payer_name := nullif(btrim(regexp_replace(new.payer_name, '\s+', ' ', 'g')), '');
  if new.payer_name is null then return new; end if;
  if length(new.payer_name) > 120 then
    raise exception 'Имя плательщика должно быть не длиннее 120 символов';
  end if;
  insert into public.project_payers(user_id, project_id, name)
  values (new.user_id, new.project_id, new.payer_name)
  on conflict (project_id, lower(name)) do nothing;
  select name into canonical_name from public.project_payers
  where project_id = new.project_id and lower(name) = lower(new.payer_name);
  new.payer_name := coalesce(canonical_name, new.payer_name);
  return new;
end;
$$;
create trigger project_transactions_remember_payer
before insert or update of payer_name on public.project_transactions
for each row execute function public.remember_project_payer();

commit;
