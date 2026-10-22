-- Проверил права на временных аккаунтах; все изменения откатил в конце.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  member_id uuid := gen_random_uuid();
  team_id uuid := gen_random_uuid();
  access jsonb;
begin
  insert into auth.users(id, email, raw_user_meta_data)
  values (owner_id, owner_id::text || '@example.invalid', '{}'::jsonb),
         (member_id, member_id::text || '@example.invalid', '{}'::jsonb);
  insert into public.teams(id, owner_user_id, name) values (team_id, owner_id, 'Проверка подписки');
  insert into public.team_members(team_id, user_id, role)
  values (team_id, owner_id, 'owner'), (team_id, member_id, 'member');

  update public.profiles set subscription_plan = 'team', subscription_status = 'active',
    subscription_renews_at = now() - interval '1 day' where id = owner_id;
  perform set_config('request.jwt.claim.sub', member_id::text, true);
  access := public.subscription_access();
  if access->>'subscription_plan' <> 'team'
    or (access->>'subscription_renews_at')::timestamptz > now()
    or not (access->>'subscription_team_managed')::boolean then
    raise exception 'Не удалось определить истёкший доступ участника';
  end if;
  if (select is_active from public.team_workspace()) then
    raise exception 'У истёкшей бригады остались преимущества';
  end if;

  update public.profiles set subscription_plan = 'basic', subscription_renews_at = null where id = owner_id;
  if (select subscription_plan from public.profiles where id = member_id) <> 'basic' then
    raise exception 'Участник не переведён на Базовый';
  end if;
  update public.profiles set subscription_plan = 'team', subscription_status = 'active',
    subscription_renews_at = now() + interval '30 days' where id = owner_id;
  if (select subscription_plan from public.profiles where id = member_id) <> 'team' then
    raise exception 'Продление не вернуло доступ участнику';
  end if;
  if not (select is_active from public.team_workspace()) then
    raise exception 'Продлённая бригада осталась неактивной';
  end if;
  update public.profiles set subscription_status = 'canceled' where id = owner_id;
  access := public.subscription_access();
  if access->>'subscription_status' <> 'canceled' then
    raise exception 'Отмена подписки не отразилась у участника';
  end if;
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  if public.subscription_access() is not null then
    raise exception 'Вернулись чужие права';
  end if;
  raise notice 'Проверены: истечение, отключение, продление, отмена, изоляция пользователей';
end;
$$;
rollback;
