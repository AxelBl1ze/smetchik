alter table public.promo_codes
drop constraint if exists promo_codes_plan_check;

alter table public.promo_codes
add constraint promo_codes_plan_check check (plan in ('pro', 'team'));

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
begin
  if v_user_id is null then raise exception 'Требуется авторизация.'; end if;
  if length(v_code) < 4 or length(v_code) > 48 then raise exception 'Проверьте промокод.'; end if;
  select * into v_promo from public.promo_codes where code_hash = encode(digest(v_code, 'sha256'), 'hex') for update;
  if not found or not v_promo.is_active then raise exception 'Промокод не найден или больше не действует.'; end if;
  if v_promo.starts_at is not null and v_promo.starts_at > now() then raise exception 'Промокод ещё не начал действовать.'; end if;
  if v_promo.expires_at is not null and v_promo.expires_at <= now() then raise exception 'Срок действия промокода закончился.'; end if;
  if v_promo.redemption_count >= v_promo.max_redemptions then raise exception 'Лимит активаций этого промокода исчерпан.'; end if;
  if exists (select 1 from public.promo_redemptions where promo_id = v_promo.id and user_id = v_user_id) then raise exception 'Этот промокод уже был использован в вашем аккаунте.'; end if;
  select * into v_profile from public.profiles where id = v_user_id for update;
  if not found then raise exception 'Профиль не найден. Войдите в приложение ещё раз.'; end if;
  v_renews_at := greatest(coalesce(v_profile.subscription_renews_at, now()), now()) + make_interval(days => v_promo.grant_days);
  perform set_config('app.smetchik.subscription_change', 'allowed', true);
  update public.profiles set subscription_plan = v_promo.plan, subscription_status = 'active', subscription_source = 'promo', subscription_renews_at = v_renews_at where id = v_user_id;
  insert into public.promo_redemptions (promo_id, user_id, subscription_plan_before, subscription_renews_at_before, granted_until) values (v_promo.id, v_user_id, v_profile.subscription_plan, v_profile.subscription_renews_at, v_renews_at);
  update public.promo_codes set redemption_count = redemption_count + 1 where id = v_promo.id;
  insert into public.admin_audit_events (actor_user_id, action, entity_type, entity_id, metadata) values (v_user_id, 'promo_redeemed', 'promo_code', v_promo.id::text, jsonb_build_object('title', v_promo.title, 'plan', v_promo.plan, 'grant_days', v_promo.grant_days));
  return query select v_promo.plan, v_renews_at, v_promo.title;
end;
$$;
