alter table public.estimates
add column if not exists document_version integer not null default 1,
add column if not exists revision_of uuid references public.estimates(id) on delete restrict,
add column if not exists signed_pdf_storage_path text,
add column if not exists signed_document_snapshot jsonb,
add column if not exists client_signed_name text,
add column if not exists client_signed_phone text,
add column if not exists client_signature_statement_version text,
add column if not exists client_signature_statement text;

alter table public.estimates
drop constraint if exists estimates_document_version_check;

alter table public.estimates
add constraint estimates_document_version_check check (document_version >= 1);

create index if not exists estimates_revision_of_idx
on public.estimates(revision_of);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('signed-estimate-pdfs', 'signed-estimate-pdfs', true, 10485760, array['application/pdf'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read signed estimate pdfs"
on storage.objects for select
using (bucket_id = 'signed-estimate-pdfs');

create policy "Users write own signed estimate pdfs"
on storage.objects for insert
with check (bucket_id = 'signed-estimate-pdfs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update own client signatures" on storage.objects;

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
      or new.client_signature_statement is distinct from old.client_signature_statement then
      raise exception 'Подписанную смету нельзя изменить. Создайте новую версию.';
    end if;

    if new.status not in ('accepted', 'in_progress', 'completed') then
      raise exception 'Нельзя вернуть подписанную смету в неподтверждённый статус.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists a_prevent_signed_estimate_mutation on public.estimates;
create trigger a_prevent_signed_estimate_mutation
before update or delete on public.estimates
for each row execute function public.prevent_signed_estimate_mutation();

create or replace function public.prevent_signed_estimate_line_mutation()
returns trigger
language plpgsql
as $$
declare
  target_estimate_id uuid;
  is_signed boolean;
begin
  target_estimate_id := case
    when tg_op = 'DELETE' then old.estimate_id
    else new.estimate_id
  end;

  select client_signed_at is not null
  into is_signed
  from public.estimates
  where id = target_estimate_id;

  if coalesce(is_signed, false) then
    raise exception 'Строки подписанной сметы нельзя изменить. Создайте новую версию.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_signed_estimate_line_mutation on public.estimate_lines;
create trigger prevent_signed_estimate_line_mutation
before insert or update or delete on public.estimate_lines
for each row execute function public.prevent_signed_estimate_line_mutation();
