alter table public.promo_codes
add column if not exists unlimited_redemptions boolean not null default false;

create or replace function public.redeem_promo(p_code text)
returns table (
  subscription_plan text,
  subscription_renews_at timestamptz,
  promo_title text
)
language plpgsql
security definer set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_promo public.promo_codes%rowtype;
  v_profile public.profiles%rowtype;
  v_renews_at timestamptz;
  v_team public.teams%rowtype;
begin
  if v_user_id is null then raise exception 'Требуется авторизация.'; end if;
  if length(v_code) < 4 or length(v_code) > 48 then raise exception 'Проверьте промокод.'; end if;

  select * into v_promo
  from public.promo_codes
  where code_hash = encode(extensions.digest(v_code, 'sha256'), 'hex')
  for update;

  if not found or not v_promo.is_active then raise exception 'Промокод не найден или больше не действует.'; end if;
  if v_promo.starts_at is not null and v_promo.starts_at > now() then raise exception 'Промокод ещё не начал действовать.'; end if;
  if v_promo.expires_at is not null and v_promo.expires_at <= now() then raise exception 'Срок действия промокода закончился.'; end if;
  if not v_promo.unlimited_redemptions and v_promo.redemption_count >= v_promo.max_redemptions then
    raise exception 'Лимит активаций этого промокода исчерпан.';
  end if;
  if exists (select 1 from public.promo_redemptions where promo_id = v_promo.id and user_id = v_user_id) then
    raise exception 'Этот промокод уже был использован в вашем аккаунте.';
  end if;

  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then raise exception 'Профиль не найден. Войдите в приложение ещё раз.'; end if;

  if v_promo.plan = 'team' and exists (
    select 1 from public.team_members where user_id = v_user_id and role <> 'owner'
  ) then
    raise exception 'Участник уже состоит в бригаде. Тариф Бригада продлевает её владелец.';
  end if;

  v_renews_at := greatest(coalesce(v_profile.subscription_renews_at, now()), now())
    + make_interval(days => v_promo.grant_days);

  perform set_config('app.smetchik.subscription_change', 'allowed', true);
  update public.profiles
  set subscription_plan = v_promo.plan,
      subscription_status = 'active',
      subscription_source = 'promo',
      subscription_renews_at = v_renews_at
  where id = v_user_id;

  if v_promo.plan = 'team' then
    select * into v_team from public.teams where owner_user_id = v_user_id for update;
    if not found then
      insert into public.teams (owner_user_id, name, max_members)
      values (v_user_id, 'Моя бригада', v_promo.team_max_members)
      returning * into v_team;
      insert into public.team_members (team_id, user_id, role, member_name, member_email)
      select v_team.id, v_user_id, 'owner', full_name, coalesce(auth.jwt() ->> 'email', '')
      from public.profiles where id = v_user_id;
    else
      update public.teams
      set max_members = greatest(max_members, v_promo.team_max_members)
      where id = v_team.id
      returning * into v_team;
    end if;
  end if;

  insert into public.promo_redemptions (
    promo_id, user_id, subscription_plan_before, subscription_renews_at_before, granted_until
  ) values (
    v_promo.id, v_user_id, v_profile.subscription_plan, v_profile.subscription_renews_at, v_renews_at
  );

  update public.promo_codes
  set redemption_count = redemption_count + 1,
      is_active = case
        when not unlimited_redemptions and redemption_count + 1 >= max_redemptions then false
        else is_active
      end,
      disabled_at = case
        when not unlimited_redemptions and redemption_count + 1 >= max_redemptions then now()
        else disabled_at
      end
  where id = v_promo.id;

  insert into public.admin_audit_events (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    v_user_id, 'promo_redeemed', 'promo_code', v_promo.id::text,
    jsonb_build_object(
      'title', v_promo.title,
      'plan', v_promo.plan,
      'grant_days', v_promo.grant_days,
      'team_max_members', case when v_promo.plan = 'team' then v_promo.team_max_members else null end,
      'unlimited_redemptions', v_promo.unlimited_redemptions
    )
  );

  return query select v_promo.plan, v_renews_at, v_promo.title;
end;
$$;
