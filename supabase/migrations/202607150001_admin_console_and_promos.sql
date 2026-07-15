create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  label text,
  enabled boolean not null default true,
  granted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists app_admins_email_lower_idx
on public.app_admins (lower(email));

alter table public.app_admins enable row level security;
revoke all on public.app_admins from anon, authenticated;

create table if not exists public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  code_hint text not null,
  title text not null,
  plan text not null default 'pro' check (plan in ('pro')),
  grant_days integer not null check (grant_days between 1 and 1095),
  max_redemptions integer not null default 1 check (max_redemptions between 1 and 100000),
  redemption_count integer not null default 0 check (redemption_count >= 0),
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

create index if not exists promo_codes_active_idx
on public.promo_codes (is_active, expires_at, created_at desc);

drop trigger if exists promo_codes_updated_at on public.promo_codes;
create trigger promo_codes_updated_at
before update on public.promo_codes
for each row execute function public.set_updated_at();

alter table public.promo_codes enable row level security;
revoke all on public.promo_codes from anon, authenticated;

create table if not exists public.promo_redemptions (
  id uuid primary key default gen_random_uuid(),
  promo_id uuid not null references public.promo_codes(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  subscription_plan_before text,
  subscription_renews_at_before timestamptz,
  granted_until timestamptz not null,
  redeemed_at timestamptz not null default now(),
  unique (promo_id, user_id)
);

create index if not exists promo_redemptions_user_idx
on public.promo_redemptions (user_id, redeemed_at desc);

alter table public.promo_redemptions enable row level security;
revoke all on public.promo_redemptions from anon, authenticated;

create table if not exists public.admin_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_events_created_idx
on public.admin_audit_events (created_at desc);

create index if not exists admin_audit_events_entity_idx
on public.admin_audit_events (entity_type, entity_id, created_at desc);

alter table public.admin_audit_events enable row level security;
revoke all on public.admin_audit_events from anon, authenticated;

alter table public.profiles
drop constraint if exists profiles_subscription_source_check;

alter table public.profiles
add constraint profiles_subscription_source_check
check (
  subscription_source in (
    'manual', 'mock', 'web', 'google_play', 'apple', 'promo', 'admin'
  )
);

create or replace function public.is_smetchik_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists (
    select 1
    from public.app_admins
    where user_id = auth.uid()
      and enabled = true
  );
$$;

revoke all on function public.is_smetchik_admin() from public;
grant execute on function public.is_smetchik_admin() to authenticated, service_role;

create or replace function public.prevent_client_subscription_mutation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if old.subscription_plan is distinct from new.subscription_plan
    or old.subscription_status is distinct from new.subscription_status
    or old.subscription_source is distinct from new.subscription_source
    or old.subscription_renews_at is distinct from new.subscription_renews_at then
    if current_setting('request.jwt.claim.role', true) = 'authenticated'
      and coalesce(
        current_setting('app.smetchik.subscription_change', true),
        ''
      ) <> 'allowed' then
      raise exception 'Тариф меняется только через защищённый серверный сценарий.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_client_subscription_mutation on public.profiles;
create trigger prevent_client_subscription_mutation
before update on public.profiles
for each row execute function public.prevent_client_subscription_mutation();

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
  v_base timestamptz;
  v_renews_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Требуется авторизация.';
  end if;
  if length(v_code) < 4 or length(v_code) > 48 then
    raise exception 'Проверьте промокод.';
  end if;

  select * into v_promo
  from public.promo_codes
  where code_hash = encode(digest(v_code, 'sha256'), 'hex')
  for update;

  if not found or not v_promo.is_active then
    raise exception 'Промокод не найден или больше не действует.';
  end if;
  if v_promo.starts_at is not null and v_promo.starts_at > now() then
    raise exception 'Промокод ещё не начал действовать.';
  end if;
  if v_promo.expires_at is not null and v_promo.expires_at <= now() then
    raise exception 'Срок действия промокода закончился.';
  end if;
  if v_promo.redemption_count >= v_promo.max_redemptions then
    raise exception 'Лимит активаций этого промокода исчерпан.';
  end if;
  if exists (
    select 1 from public.promo_redemptions
    where promo_id = v_promo.id and user_id = v_user_id
  ) then
    raise exception 'Этот промокод уже был использован в вашем аккаунте.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  if not found then
    raise exception 'Профиль не найден. Войдите в приложение ещё раз.';
  end if;

  v_base := greatest(coalesce(v_profile.subscription_renews_at, now()), now());
  v_renews_at := v_base + make_interval(days => v_promo.grant_days);

  perform set_config('app.smetchik.subscription_change', 'allowed', true);

  update public.profiles
  set subscription_plan = 'pro',
      subscription_status = 'active',
      subscription_source = 'promo',
      subscription_renews_at = v_renews_at
  where id = v_user_id;

  insert into public.promo_redemptions (
    promo_id,
    user_id,
    subscription_plan_before,
    subscription_renews_at_before,
    granted_until
  ) values (
    v_promo.id,
    v_user_id,
    v_profile.subscription_plan,
    v_profile.subscription_renews_at,
    v_renews_at
  );

  update public.promo_codes
  set redemption_count = redemption_count + 1
  where id = v_promo.id;

  insert into public.admin_audit_events (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    v_user_id,
    'promo_redeemed',
    'promo_code',
    v_promo.id::text,
    jsonb_build_object('title', v_promo.title, 'grant_days', v_promo.grant_days)
  );

  return query
  select 'pro'::text, v_renews_at, v_promo.title;
end;
$$;

revoke all on function public.redeem_promo(text) from public, anon;
grant execute on function public.redeem_promo(text) to authenticated, service_role;

insert into public.app_admins (user_id, email, label)
select id, lower(email), 'Основатель'
from auth.users
where lower(coalesce(email, '')) = 'ilyasidnev.qa@gmail.com'
on conflict (user_id) do update
set email = excluded.email,
    label = excluded.label,
    enabled = true;

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

  if coalesce(new.raw_user_meta_data ->> 'legal_terms_version', '') <> '' then
    insert into public.legal_acceptances (
      user_id, document_id, document_version, accepted_at, source
    ) values (
      new.id,
      'terms',
      new.raw_user_meta_data ->> 'legal_terms_version',
      coalesce(
        nullif(new.raw_user_meta_data ->> 'legal_accepted_at', '')::timestamptz,
        now()
      ),
      'signup'
    ) on conflict (user_id, document_id, document_version) do nothing;
  end if;

  if coalesce(new.raw_user_meta_data ->> 'legal_privacy_version', '') <> '' then
    insert into public.legal_acceptances (
      user_id, document_id, document_version, accepted_at, source
    ) values (
      new.id,
      'privacy',
      new.raw_user_meta_data ->> 'legal_privacy_version',
      coalesce(
        nullif(new.raw_user_meta_data ->> 'legal_accepted_at', '')::timestamptz,
        now()
      ),
      'signup'
    ) on conflict (user_id, document_id, document_version) do nothing;
  end if;

  if lower(coalesce(new.email, '')) = 'ilyasidnev.qa@gmail.com' then
    insert into public.app_admins (user_id, email, label)
    values (new.id, lower(new.email), 'Основатель')
    on conflict (user_id) do update
    set email = excluded.email,
        label = excluded.label,
        enabled = true;
  end if;

  return new;
end;
$$;
