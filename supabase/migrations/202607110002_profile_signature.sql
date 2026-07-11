alter table public.profiles
add column if not exists signature_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('signatures', 'signatures', true, 1048576, array['image/png'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read signatures"
on storage.objects for select
using (bucket_id = 'signatures');

create policy "Users write own signatures"
on storage.objects for insert
with check (bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update own signatures"
on storage.objects for update
using (bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'signatures' and (storage.foldername(name))[1] = auth.uid()::text);
