-- Profile images may be replaced many times. Give a user permission to remove
-- only their own previous avatar, signature and QR image after the replacement
-- has been saved in profiles. Immutable signed documents are not covered.

create policy "Users delete own profile logos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'logos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users delete own profile signatures"
on storage.objects for delete to authenticated
using (
  bucket_id = 'signatures'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "Users delete own profile qr codes"
on storage.objects for delete to authenticated
using (
  bucket_id = 'qr-codes'
  and (storage.foldername(name))[1] = auth.uid()::text
);
