-- Restore the seat count selected by the latest Team promo for owners who
-- created their workspace separately, and repair an owner membership if an
-- earlier interrupted flow left the team without it.
with latest_team_promo as (
  select distinct on (redemption.user_id)
    redemption.user_id,
    promo.team_max_members
  from public.promo_redemptions redemption
  join public.promo_codes promo on promo.id = redemption.promo_id
  where promo.plan = 'team'
  order by redemption.user_id, redemption.redeemed_at desc
)
update public.teams team
set max_members = greatest(team.max_members, latest_team_promo.team_max_members)
from latest_team_promo
where team.owner_user_id = latest_team_promo.user_id;

insert into public.team_members (
  team_id,
  user_id,
  role,
  member_name,
  member_email
)
select
  team.id,
  team.owner_user_id,
  'owner',
  profile.full_name,
  coalesce(auth_user.email, '')
from public.teams team
join public.profiles profile on profile.id = team.owner_user_id
left join auth.users auth_user on auth_user.id = team.owner_user_id
where not exists (
  select 1
  from public.team_members member
  where member.team_id = team.id
    and member.user_id = team.owner_user_id
)
on conflict (team_id, user_id) do nothing;

create or replace function public.create_team(p_name text default 'Моя бригада')
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_profile public.profiles%rowtype;
  v_max_members integer := 6;
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

  select greatest(6, promo.team_max_members)
  into v_max_members
  from public.promo_redemptions redemption
  join public.promo_codes promo on promo.id = redemption.promo_id
  where redemption.user_id = v_user_id
    and promo.plan = 'team'
  order by redemption.redeemed_at desc
  limit 1;

  v_max_members := coalesce(v_max_members, 6);

  select id into v_team_id from public.teams where owner_user_id = v_user_id;
  if v_team_id is not null then
    update public.teams
    set max_members = greatest(max_members, v_max_members)
    where id = v_team_id;
    return v_team_id;
  end if;

  insert into public.teams (owner_user_id, name, max_members)
  values (
    v_user_id,
    coalesce(nullif(trim(p_name), ''), 'Моя бригада'),
    v_max_members
  )
  returning id into v_team_id;

  insert into public.team_members (team_id, user_id, role, member_name, member_email)
  select v_team_id, v_user_id, 'owner', full_name, coalesce((auth.jwt() ->> 'email'), '')
  from public.profiles where id = v_user_id;

  return v_team_id;
end;
$$;
