begin;

-- Права участников всегда определяю по подписке владельца, включая истечение по времени.
create or replace function public.subscription_access()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'subscription_plan', case when tm.role = 'member' then
      case when owner_profile.subscription_plan = 'team' then 'team' else 'basic' end
      else p.subscription_plan end,
    'subscription_status', case when tm.role = 'member' then owner_profile.subscription_status else p.subscription_status end,
    'subscription_source', case when tm.role = 'member' then 'admin' else p.subscription_source end,
    'subscription_renews_at', case when tm.role = 'member' then owner_profile.subscription_renews_at else p.subscription_renews_at end,
    'subscription_team_managed', tm.user_id is not null,
    'subscription_owner_name', owner_profile.full_name
  )
  from public.profiles p
  left join public.team_members tm on tm.user_id = p.id
  left join public.teams t on t.id = tm.team_id
  left join public.profiles owner_profile on owner_profile.id = t.owner_user_id
  where p.id = auth.uid();
$$;
revoke all on function public.subscription_access() from public;
grant execute on function public.subscription_access() to authenticated;

create or replace function public.sync_team_subscription_to_members()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.subscription_plan is not distinct from new.subscription_plan
    and old.subscription_status is not distinct from new.subscription_status
    and old.subscription_renews_at is not distinct from new.subscription_renews_at then return new; end if;
  if exists (select 1 from public.teams where owner_user_id = new.id) then
    perform set_config('app.smetchik.subscription_change', 'allowed', true);
    update public.profiles p set
      subscription_plan = case when new.subscription_plan = 'team' then 'team' else 'basic' end,
      subscription_status = case when new.subscription_plan = 'team' then new.subscription_status else 'active' end,
      subscription_source = case when new.subscription_plan = 'team' then 'admin' else 'manual' end,
      subscription_renews_at = case when new.subscription_plan = 'team' then new.subscription_renews_at else null end
    where p.id in (select tm.user_id from public.team_members tm join public.teams t on t.id = tm.team_id
      where t.owner_user_id = new.id and tm.user_id <> new.id);
  end if;
  return new;
end;
$$;

-- Починил старые скопированные права, сохранив состав бригад.
update public.profiles member_profile set
  subscription_plan = case when owner_profile.subscription_plan = 'team' then 'team' else 'basic' end,
  subscription_status = case when owner_profile.subscription_plan = 'team' then owner_profile.subscription_status else 'active' end,
  subscription_source = case when owner_profile.subscription_plan = 'team' then 'admin' else 'manual' end,
  subscription_renews_at = case when owner_profile.subscription_plan = 'team' then owner_profile.subscription_renews_at else null end
from public.team_members tm join public.teams t on t.id = tm.team_id
join public.profiles owner_profile on owner_profile.id = t.owner_user_id
where tm.user_id = member_profile.id and tm.role = 'member';

commit;
