alter table public.estimates
add column if not exists completion_act_storage_path text,
add column if not exists completion_act_generated_at timestamptz;

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
      or (old.completion_act_storage_path is not null
        and new.completion_act_storage_path is distinct from old.completion_act_storage_path)
      or (old.completion_act_generated_at is not null
        and new.completion_act_generated_at is distinct from old.completion_act_generated_at)
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
