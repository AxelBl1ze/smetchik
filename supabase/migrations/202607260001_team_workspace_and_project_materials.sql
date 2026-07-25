-- Materials are planned separately from the actual expense transaction.
create table if not exists public.project_materials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null,
  planned_quantity numeric(12, 3) not null default 1 check (planned_quantity > 0),
  unit text not null default 'шт',
  planned_unit_price numeric(12, 2) not null default 0 check (planned_unit_price >= 0),
  actual_quantity numeric(12, 3),
  actual_amount numeric(12, 2),
  purchased_at date,
  purchase_transaction_id uuid references public.project_transactions(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists project_materials_project_idx
on public.project_materials(project_id, created_at desc);

alter table public.project_materials enable row level security;

create policy "Users manage own project materials"
on public.project_materials for all to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.projects
    where projects.id = project_id and projects.user_id = auth.uid()
  )
);

drop trigger if exists project_materials_updated_at on public.project_materials;
create trigger project_materials_updated_at
before update on public.project_materials
for each row execute function public.set_updated_at();

-- Team is a paid workspace: one owner pays, up to five additional masters use
-- their own accounts. Members do not gain access to private clients or estimates.
alter table public.profiles
drop constraint if exists profiles_subscription_plan_check;

alter table public.profiles
add constraint profiles_subscription_plan_check
check (subscription_plan in ('basic', 'pro', 'team'));

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null default 'Моя бригада',
  max_members integer not null default 6 check (max_members between 2 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  member_name text not null default '',
  member_email text not null default '',
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table if not exists public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  invited_email text not null,
  role text not null default 'member' check (role = 'member'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  cancelled_at timestamptz,
  unique (team_id, invited_email)
);

create index if not exists team_invites_email_idx
on public.team_invites(lower(invited_email), expires_at desc);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_invites enable row level security;

-- The app uses the RPC functions below. Keeping direct table access closed
-- prevents a member from discovering someone else's private profile data.
revoke all on public.teams, public.team_members, public.team_invites from anon, authenticated;

drop trigger if exists teams_updated_at on public.teams;
create trigger teams_updated_at
before update on public.teams
for each row execute function public.set_updated_at();

create or replace function public.team_workspace()
returns table (
  team_id uuid,
  team_name text,
  owner_user_id uuid,
  member_role text,
  max_members integer,
  seats_used integer,
  subscription_renews_at timestamptz,
  is_active boolean
)
language sql
stable
security definer set search_path = public
as $$
  select
    t.id,
    t.name,
    t.owner_user_id,
    tm.role,
    t.max_members,
    (select count(*)::integer from public.team_members all_members where all_members.team_id = t.id),
    owner_profile.subscription_renews_at,
    owner_profile.subscription_plan = 'team'
      and owner_profile.subscription_status in ('active', 'trialing')
      and (owner_profile.subscription_renews_at is null or owner_profile.subscription_renews_at > now())
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  join public.profiles owner_profile on owner_profile.id = t.owner_user_id
  where tm.user_id = auth.uid();
$$;

create or replace function public.team_members_list()
returns table (
  user_id uuid,
  member_name text,
  member_email text,
  member_role text,
  joined_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select tm.user_id, tm.member_name, tm.member_email, tm.role, tm.joined_at
  from public.team_members tm
  where tm.team_id = (
    select own_membership.team_id
    from public.team_members own_membership
    where own_membership.user_id = auth.uid()
  )
  order by case when tm.role = 'owner' then 0 else 1 end, tm.joined_at;
$$;

create or replace function public.team_invites_list()
returns table (
  invite_id uuid,
  invited_email text,
  expires_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select i.id, i.invited_email, i.expires_at
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  where t.owner_user_id = auth.uid()
    and i.accepted_at is null
    and i.cancelled_at is null
    and i.expires_at > now()
  order by i.created_at desc;
$$;

create or replace function public.incoming_team_invites()
returns table (
  invite_id uuid,
  team_name text,
  owner_name text,
  expires_at timestamptz
)
language sql
stable
security definer set search_path = public
as $$
  select i.id, t.name, owner_profile.full_name, i.expires_at
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  join public.profiles owner_profile on owner_profile.id = t.owner_user_id
  where lower(i.invited_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and i.accepted_at is null
    and i.cancelled_at is null
    and i.expires_at > now()
  order by i.created_at desc;
$$;

create or replace function public.create_team(p_name text default 'Моя бригада')
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация.';
  end if;

  select * into v_profile from public.profiles where id = v_user_id;
  if not found
    or v_profile.subscription_plan <> 'team'
    or v_profile.subscription_status not in ('active', 'trialing')
    or (v_profile.subscription_renews_at is not null and v_profile.subscription_renews_at <= now()) then
    raise exception 'Для создания бригады нужен активный тариф Бригада.';
  end if;

  select id into v_team_id from public.teams where owner_user_id = v_user_id;
  if v_team_id is not null then
    return v_team_id;
  end if;

  insert into public.teams (owner_user_id, name)
  values (v_user_id, coalesce(nullif(trim(p_name), ''), 'Моя бригада'))
  returning id into v_team_id;

  insert into public.team_members (team_id, user_id, role, member_name, member_email)
  select v_team_id, v_user_id, 'owner', full_name, coalesce((auth.jwt() ->> 'email'), '')
  from public.profiles where id = v_user_id;

  return v_team_id;
end;
$$;

create or replace function public.invite_team_member(p_email text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_team public.teams%rowtype;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_count integer;
  v_invite_id uuid;
begin
  if v_user_id is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Введите корректный email мастера.';
  end if;
  select * into v_team from public.teams where owner_user_id = v_user_id;
  if not found then
    raise exception 'Создайте бригаду перед приглашением.';
  end if;
  select count(*) into v_count from public.team_members where team_id = v_team.id;
  if v_count >= v_team.max_members then
    raise exception 'В бригаде заняты все места.';
  end if;
  if exists (select 1 from public.team_members where team_id = v_team.id and lower(member_email) = v_email) then
    raise exception 'Этот мастер уже состоит в бригаде.';
  end if;

  insert into public.team_invites (team_id, invited_email)
  values (v_team.id, v_email)
  on conflict (team_id, invited_email) do update
    set expires_at = now() + interval '14 days', accepted_at = null, cancelled_at = null
  returning id into v_invite_id;
  return v_invite_id;
end;
$$;

create or replace function public.accept_team_invite(p_invite_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  v_invite public.team_invites%rowtype;
  v_team public.teams%rowtype;
  v_count integer;
  v_owner_profile public.profiles%rowtype;
begin
  if v_user_id is null then raise exception 'Требуется авторизация.'; end if;
  select * into v_invite from public.team_invites where id = p_invite_id for update;
  if not found or v_invite.accepted_at is not null or v_invite.cancelled_at is not null or v_invite.expires_at <= now() then
    raise exception 'Приглашение больше не действует.';
  end if;
  if lower(v_invite.invited_email) <> v_email then
    raise exception 'Это приглашение предназначено для другого аккаунта.';
  end if;
  if exists (select 1 from public.team_members where user_id = v_user_id) then
    raise exception 'Этот аккаунт уже состоит в другой бригаде.';
  end if;
  select * into v_team from public.teams where id = v_invite.team_id;
  select count(*) into v_count from public.team_members where team_id = v_team.id;
  if v_count >= v_team.max_members then raise exception 'В бригаде заняты все места.'; end if;

  insert into public.team_members (team_id, user_id, role, member_name, member_email)
  select v_team.id, v_user_id, 'member', full_name, v_email
  from public.profiles where id = v_user_id;

  select * into v_owner_profile from public.profiles where id = v_team.owner_user_id;
  perform set_config('app.smetchik.subscription_change', 'allowed', true);
  update public.profiles
  set subscription_plan = 'team',
      subscription_status = v_owner_profile.subscription_status,
      subscription_source = 'admin',
      subscription_renews_at = v_owner_profile.subscription_renews_at
  where id = v_user_id;

  update public.team_invites set accepted_at = now() where id = v_invite.id;
  return v_team.id;
end;
$$;

create or replace function public.remove_team_member(p_member_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_team_id uuid;
begin
  select id into v_team_id from public.teams where owner_user_id = auth.uid();
  if v_team_id is null then raise exception 'Только владелец может менять состав бригады.'; end if;
  if p_member_id = auth.uid() then raise exception 'Владелец не может удалить себя из бригады.'; end if;
  if not exists (select 1 from public.team_members where team_id = v_team_id and user_id = p_member_id) then
    raise exception 'Мастер не состоит в этой бригаде.';
  end if;
  delete from public.team_members where team_id = v_team_id and user_id = p_member_id;
  perform set_config('app.smetchik.subscription_change', 'allowed', true);
  update public.profiles
  set subscription_plan = 'basic', subscription_status = 'active', subscription_source = 'manual', subscription_renews_at = null
  where id = p_member_id and subscription_plan = 'team';
end;
$$;

create or replace function public.sync_team_subscription_to_members()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.subscription_plan is not distinct from new.subscription_plan
    and old.subscription_status is not distinct from new.subscription_status
    and old.subscription_renews_at is not distinct from new.subscription_renews_at then
    return new;
  end if;
  if exists (select 1 from public.teams where owner_user_id = new.id) then
    perform set_config('app.smetchik.subscription_change', 'allowed', true);
    update public.profiles member_profile
    set subscription_plan = case when new.subscription_plan = 'team' then 'team' else 'basic' end,
        subscription_status = case when new.subscription_plan = 'team' then new.subscription_status else 'active' end,
        subscription_source = case when new.subscription_plan = 'team' then 'admin' else 'manual' end,
        subscription_renews_at = case when new.subscription_plan = 'team' then new.subscription_renews_at else null end
    where member_profile.id in (
      select user_id from public.team_members where team_id = (select id from public.teams where owner_user_id = new.id) and user_id <> new.id
    )
      and member_profile.subscription_plan = 'team';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_team_subscription_to_members on public.profiles;
create trigger sync_team_subscription_to_members
after update of subscription_plan, subscription_status, subscription_renews_at on public.profiles
for each row execute function public.sync_team_subscription_to_members();

revoke all on function public.team_workspace() from public;
revoke all on function public.team_members_list() from public;
revoke all on function public.team_invites_list() from public;
revoke all on function public.incoming_team_invites() from public;
revoke all on function public.create_team(text) from public;
revoke all on function public.invite_team_member(text) from public;
revoke all on function public.accept_team_invite(uuid) from public;
revoke all on function public.remove_team_member(uuid) from public;

grant execute on function public.team_workspace() to authenticated, service_role;
grant execute on function public.team_members_list() to authenticated, service_role;
grant execute on function public.team_invites_list() to authenticated, service_role;
grant execute on function public.incoming_team_invites() to authenticated, service_role;
grant execute on function public.create_team(text) to authenticated, service_role;
grant execute on function public.invite_team_member(text) to authenticated, service_role;
grant execute on function public.accept_team_invite(uuid) to authenticated, service_role;
grant execute on function public.remove_team_member(uuid) to authenticated, service_role;
