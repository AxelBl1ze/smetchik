create or replace function public.cancel_team_invite(p_invite_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.team_invites i
  set cancelled_at = now()
  from public.teams t
  where i.id = p_invite_id
    and i.team_id = t.id
    and t.owner_user_id = auth.uid()
    and i.accepted_at is null
    and i.cancelled_at is null;
  if not found then raise exception 'Приглашение не найдено или уже недоступно.'; end if;
end;
$$;

revoke all on function public.cancel_team_invite(uuid) from public;
grant execute on function public.cancel_team_invite(uuid) to authenticated, service_role;
