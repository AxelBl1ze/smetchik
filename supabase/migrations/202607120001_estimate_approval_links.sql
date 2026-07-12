create table if not exists public.estimate_signature_links (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  viewed_at timestamptz,
  signed_at timestamptz,
  revoked_at timestamptz,
  signed_client_name text,
  signed_client_phone text,
  signature_path text,
  statement_version text,
  signer_ip text,
  signer_user_agent text,
  document_hash text,
  created_at timestamptz not null default now()
);

create index if not exists estimate_signature_links_active_idx
on public.estimate_signature_links(estimate_id, expires_at desc)
where signed_at is null and revoked_at is null;

alter table public.estimate_signature_links enable row level security;

alter table public.estimates
add column if not exists client_signature_method text,
add column if not exists client_signature_link_id uuid
  references public.estimate_signature_links(id),
add column if not exists signed_document_hash text;

alter table public.estimates
drop constraint if exists estimates_client_signature_method_check;

alter table public.estimates
add constraint estimates_client_signature_method_check
check (
  client_signature_method is null
  or client_signature_method in ('telegram_otp', 'approval_link')
);

create index if not exists estimates_client_signature_link_idx
on public.estimates(client_signature_link_id);

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
      or (old.signed_pdf_storage_path is not null
        and new.signed_pdf_storage_path is distinct from old.signed_pdf_storage_path)
      or new.signed_document_snapshot is distinct from old.signed_document_snapshot
      or new.client_signature_path is distinct from old.client_signature_path
      or new.client_signed_at is distinct from old.client_signed_at
      or new.client_signed_name is distinct from old.client_signed_name
      or new.client_signed_phone is distinct from old.client_signed_phone
      or new.client_signature_statement_version is distinct from old.client_signature_statement_version
      or new.client_signature_statement is distinct from old.client_signature_statement
      or new.client_signature_otp_challenge_id is distinct from old.client_signature_otp_challenge_id
      or new.client_phone_verified_at is distinct from old.client_phone_verified_at
      or new.client_signature_method is distinct from old.client_signature_method
      or new.client_signature_link_id is distinct from old.client_signature_link_id
      or new.signed_document_hash is distinct from old.signed_document_hash then
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
  link_signed_at timestamptz;
begin
  if old.status is distinct from 'accepted'
    and new.status = 'accepted'
    and new.client_signed_at is null then
    raise exception 'Принятие сметы требует подписи клиента.';
  end if;

  if old.client_signed_at is null and new.client_signed_at is not null then
    if new.client_signature_method = 'telegram_otp' then
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
    elsif new.client_signature_method = 'approval_link' then
      if new.client_signature_link_id is null then
        raise exception 'Для подписи по ссылке нужен активный запрос клиента.';
      end if;

      select signed_at
      into link_signed_at
      from public.estimate_signature_links
      where id = new.client_signature_link_id
        and user_id = new.user_id
        and estimate_id = new.id
        and revoked_at is null;

      if link_signed_at is null then
        raise exception 'Ссылка для подписи не подтверждена или недоступна.';
      end if;
    else
      raise exception 'Не указан способ подтверждения подписи клиента.';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.finalize_estimate_link_signature(
  p_link_id uuid,
  p_signature_path text,
  p_client_name text,
  p_client_phone text,
  p_signed_at timestamptz,
  p_statement_version text,
  p_statement text,
  p_snapshot jsonb,
  p_document_hash text,
  p_signer_ip text,
  p_signer_user_agent text
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  target_link public.estimate_signature_links%rowtype;
  updated_estimate_id uuid;
begin
  select *
  into target_link
  from public.estimate_signature_links
  where id = p_link_id
  for update;

  if not found
    or target_link.revoked_at is not null
    or target_link.signed_at is not null
    or target_link.expires_at <= now() then
    raise exception 'Ссылка для подписи недействительна.';
  end if;

  update public.estimate_signature_links
  set signed_at = p_signed_at,
      signed_client_name = p_client_name,
      signed_client_phone = p_client_phone,
      signature_path = p_signature_path,
      statement_version = p_statement_version,
      signer_ip = p_signer_ip,
      signer_user_agent = p_signer_user_agent,
      document_hash = p_document_hash
  where id = target_link.id;

  update public.estimates
  set status = 'accepted',
      client_signature_path = p_signature_path,
      client_signed_at = p_signed_at,
      client_signed_name = p_client_name,
      client_signed_phone = p_client_phone,
      client_signature_method = 'approval_link',
      client_signature_link_id = target_link.id,
      client_signature_statement_version = p_statement_version,
      client_signature_statement = p_statement,
      signed_document_snapshot = p_snapshot,
      signed_document_hash = p_document_hash
  where id = target_link.estimate_id
    and user_id = target_link.user_id
    and status = 'sent'
    and client_signed_at is null
  returning id into updated_estimate_id;

  if updated_estimate_id is null then
    raise exception 'Смета уже принята, изменена или недоступна.';
  end if;

  return updated_estimate_id;
end;
$$;

revoke all on function public.finalize_estimate_link_signature(
  uuid, text, text, text, timestamptz, text, text, jsonb, text, text, text
) from public, anon, authenticated;

grant execute on function public.finalize_estimate_link_signature(
  uuid, text, text, text, timestamptz, text, text, jsonb, text, text, text
) to service_role;
