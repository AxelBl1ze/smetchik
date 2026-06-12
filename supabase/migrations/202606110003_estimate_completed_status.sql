alter table public.estimates
drop constraint if exists estimates_status_check;

alter table public.estimates
add constraint estimates_status_check
check (status in ('draft', 'sent', 'approved', 'completed', 'declined'));
