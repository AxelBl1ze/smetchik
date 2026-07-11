create table if not exists public.estimate_signature_otp_challenges (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  client_phone text not null,
  telegram_request_id text not null unique,
  expires_at timestamptz not null,
  verified_at timestamptz,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists estimate_signature_otp_active_idx
on public.estimate_signature_otp_challenges(estimate_id, expires_at desc);

alter table public.estimate_signature_otp_challenges enable row level security;

alter table public.estimates
add column if not exists client_signature_otp_challenge_id uuid
  references public.estimate_signature_otp_challenges(id),
add column if not exists client_phone_verified_at timestamptz;

create or replace function public.prevent_signed_estimate_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.client_signed_at is not null then
      raise exception 'Подписанную смету нельзя удалить. Создайте новую версию.';
    end if;
    return old;
  end if;

  if old.client_signed_at is not null then
    if new.user_id is distinct from old.user_id
      or new.client_id is distinct from old.client_id
      or new.object_title is distinct from old.object_title
      or new.estimate_date is distinct from old.estimate_date
      or new.duration_days is distinct from old.duration_days
      or new.total_amount is distinct from old.total_amount
      or new.document_version is distinct from old.document_version
      or new.revision_of is distinct from old.revision_of
      or new.pdf_storage_path is distinct from old.pdf_storage_path
      or new.signed_pdf_storage_path is distinct from old.signed_pdf_storage_path
      or new.signed_document_snapshot is distinct from old.signed_document_snapshot
      or new.client_signature_path is distinct from old.client_signature_path
      or new.client_signed_at is distinct from old.client_signed_at
      or new.client_signed_name is distinct from old.client_signed_name
      or new.client_signed_phone is distinct from old.client_signed_phone
      or new.client_signature_statement_version is distinct from old.client_signature_statement_version
      or new.client_signature_statement is distinct from old.client_signature_statement
      or new.client_signature_otp_challenge_id is distinct from old.client_signature_otp_challenge_id
      or new.client_phone_verified_at is distinct from old.client_phone_verified_at then
      raise exception 'Подписанную смету нельзя изменить. Создайте новую версию.';
    end if;

    if new.status not in ('accepted', 'in_progress', 'completed') then
      raise exception 'Нельзя вернуть подписанную смету в неподтверждённый статус.';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.require_verified_signature_otp()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  verified_time timestamptz;
begin
  if old.status is distinct from 'accepted'
    and new.status = 'accepted'
    and new.client_signed_at is null then
    raise exception 'Принятие сметы требует подписи и подтверждения номера клиента.';
  end if;

  if old.client_signed_at is null and new.client_signed_at is not null then
    if new.client_signature_otp_challenge_id is null then
      raise exception 'Перед подписью подтвердите номер клиента одноразовым кодом.';
    end if;

    select verified_at
    into verified_time
    from public.estimate_signature_otp_challenges
    where id = new.client_signature_otp_challenge_id
      and user_id = new.user_id
      and estimate_id = new.id
      and client_phone = new.client_signed_phone
      and verified_at is not null
      and used_at is null
      and expires_at > now();

    if verified_time is null then
      raise exception 'Код клиента не подтверждён, истёк или уже использован.';
    end if;

    new.client_phone_verified_at := verified_time;
    update public.estimate_signature_otp_challenges
    set used_at = now()
    where id = new.client_signature_otp_challenge_id;
  end if;

  return new;
end;
$$;

drop trigger if exists b_require_verified_signature_otp on public.estimates;
create trigger b_require_verified_signature_otp
before update on public.estimates
for each row execute function public.require_verified_signature_otp();
