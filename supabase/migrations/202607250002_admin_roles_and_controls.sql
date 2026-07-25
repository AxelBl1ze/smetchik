alter table public.app_admins
add column if not exists role text not null default 'owner';

alter table public.app_admins
drop constraint if exists app_admins_role_check;

alter table public.app_admins
add constraint app_admins_role_check
check (role in ('owner', 'support', 'auditor'));

update public.app_admins
set role = 'owner'
where role is null;

create index if not exists app_admins_enabled_role_idx
on public.app_admins (enabled, role);
