create table if not exists public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id text not null,
  document_version text not null,
  accepted_at timestamptz not null default now(),
  source text not null default 'signup',
  created_at timestamptz not null default now(),
  unique (user_id, document_id, document_version)
);

create index if not exists legal_acceptances_user_id_idx
on public.legal_acceptances(user_id, accepted_at desc);

alter table public.legal_acceptances enable row level security;

create policy "Users read own legal acceptances"
on public.legal_acceptances for select
using (user_id = auth.uid());

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

  return new;
end;
$$;
