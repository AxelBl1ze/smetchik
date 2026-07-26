-- Public launch offer shown on the marketing site.
insert into public.promo_codes (
  code_hash,
  code_hint,
  code_value,
  title,
  plan,
  grant_days,
  team_max_members,
  max_redemptions,
  is_active
)
values (
  encode(extensions.digest('6JWX432NSDMEF7DE', 'sha256'), 'hex'),
  '6JW…F7DE',
  '6JWX432NSDMEF7DE',
  'Профи на 7 дней',
  'pro',
  7,
  6,
  100000,
  true
)
on conflict (code_hash) do update
set code_hint = excluded.code_hint,
    code_value = excluded.code_value,
    title = excluded.title,
    plan = excluded.plan,
    grant_days = excluded.grant_days,
    team_max_members = excluded.team_max_members,
    max_redemptions = greatest(public.promo_codes.max_redemptions, excluded.max_redemptions),
    is_active = true,
    disabled_at = null;
