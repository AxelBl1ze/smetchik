-- Встроенная поддержка. Пользователь видит только собственные обращения,
-- а сотрудники работают с ними через защищённую Edge Function.

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null check (char_length(trim(subject)) between 3 and 120),
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'waiting_user', 'resolved')),
  context jsonb not null default '{}'::jsonb,
  last_message_preview text,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_tickets_user_updated_idx
on public.support_tickets (user_id, updated_at desc);

create index if not exists support_tickets_status_updated_idx
on public.support_tickets (status, updated_at desc);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  author_user_id uuid references auth.users(id) on delete set null,
  author_role text not null check (author_role in ('user', 'support', 'system')),
  body text not null check (char_length(trim(body)) between 1 and 4000),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists support_messages_ticket_created_idx
on public.support_messages (ticket_id, created_at);

create or replace function public.sync_support_ticket_after_message()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.support_tickets
  set last_message_preview = left(trim(new.body), 180),
      last_message_at = new.created_at,
      updated_at = new.created_at,
      status = case
        when new.author_role = 'user' and status = 'waiting_user' then 'in_progress'
        else status
      end
  where id = new.ticket_id;
  return new;
end;
$$;

drop trigger if exists support_messages_sync_ticket on public.support_messages;
create trigger support_messages_sync_ticket
after insert on public.support_messages
for each row execute function public.sync_support_ticket_after_message();

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;

create policy "Users read own support tickets"
on public.support_tickets
for select to authenticated
using (user_id = auth.uid());

create policy "Users create own support tickets"
on public.support_tickets
for insert to authenticated
with check (user_id = auth.uid());

create policy "Users read messages from own tickets"
on public.support_messages
for select to authenticated
using (
  exists (
    select 1 from public.support_tickets ticket
    where ticket.id = support_messages.ticket_id
      and ticket.user_id = auth.uid()
  )
);

create policy "Users send messages to own tickets"
on public.support_messages
for insert to authenticated
with check (
  author_role = 'user'
  and author_user_id = auth.uid()
  and exists (
    select 1 from public.support_tickets ticket
    where ticket.id = support_messages.ticket_id
      and ticket.user_id = auth.uid()
      and ticket.status <> 'resolved'
  )
);

revoke all on public.support_tickets, public.support_messages from anon;
grant select, insert on public.support_tickets to authenticated;
grant select, insert on public.support_messages to authenticated;
