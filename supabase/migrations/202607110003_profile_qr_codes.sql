alter table public.profiles
add column if not exists payment_qr_path text,
add column if not exists payment_qr_label text,
add column if not exists contact_qr_path text,
add column if not exists contact_qr_label text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('qr-codes', 'qr-codes', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Users read qr codes"
on storage.objects for select
using (bucket_id = 'qr-codes');

create policy "Users write own qr codes"
on storage.objects for insert
with check (bucket_id = 'qr-codes' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Users update own qr codes"
on storage.objects for update
using (bucket_id = 'qr-codes' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'qr-codes' and (storage.foldername(name))[1] = auth.uid()::text);
