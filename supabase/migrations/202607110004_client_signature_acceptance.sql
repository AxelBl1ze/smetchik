alter table public.estimates
add column if not exists client_signature_path text,
add column if not exists client_signed_at timestamptz;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('client-signatures', 'client-signatures', true, 1048576, array['image/png'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read client signatures"
on storage.objects for select
using (bucket_id = 'client-signatures');

create policy "Users write own client signatures"
on storage.objects for insert
with check (bucket_id = 'client-signatures' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update own client signatures"
on storage.objects for update
using (bucket_id = 'client-signatures' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'client-signatures' and (storage.foldername(name))[1] = auth.uid()::text);
