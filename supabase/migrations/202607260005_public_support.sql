-- Обращения без входа: заблокированный пользователь может написать по email
-- и продолжить диалог по секретной ссылке.

alter table public.support_tickets
  alter column user_id drop not null,
  add column if not exists contact_email text,
  add column if not exists public_token uuid;

create unique index if not exists support_tickets_public_token_idx
on public.support_tickets (public_token)
where public_token is not null;

alter table public.support_tickets
  drop constraint if exists support_tickets_contact_check;

alter table public.support_tickets
  add constraint support_tickets_contact_check
  check (user_id is not null or contact_email is not null);
