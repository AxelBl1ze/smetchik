begin;
do $$
declare
  owner_id uuid;
  project_id uuid := gen_random_uuid();
  room_id uuid := gen_random_uuid();
  payload jsonb := '{"name":"Кухня","width":4,"depth":3,"height":2.7,"walls":[{},{},{}],"openings":[],"finishes":[]}';
  current_revision integer;
begin
  select id into owner_id from auth.users order by created_at limit 1;
  if owner_id is null then raise exception 'Нужен существующий пользователь'; end if;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  execute 'set local role authenticated';
  insert into public.projects(id,user_id,title) values(project_id,owner_id,'Тест помещений');
  insert into public.project_rooms(id,user_id,project_id,data)
  values(room_id,owner_id,project_id,payload);
  select revision into current_revision from public.project_rooms where id=room_id;
  if current_revision <> 1 then raise exception 'Неверная начальная ревизия'; end if;
  update public.project_rooms set data=jsonb_set(data,'{name}','"Гараж"'),revision=100
  where id=room_id and revision=1;
  if (select revision from public.project_rooms where id=room_id) <> 2 then
    raise exception 'Нарушено версионирование';
  end if;
  update public.project_rooms set data=jsonb_set(data,'{name}','"Устаревшая запись"')
  where id=room_id and revision=1;
  if found then raise exception 'Устаревший клиент затёр помещение'; end if;
  begin
    insert into public.project_rooms(user_id,project_id,data) values(owner_id,project_id,'{}');
    raise exception 'Сохранено пустое помещение';
  exception when check_violation then null;
  end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  if exists(select 1 from public.project_rooms where id=room_id) then
    raise exception 'RLS позволил прочитать чужое помещение';
  end if;
  update public.project_rooms set data=data where id=room_id;
  if found then raise exception 'RLS позволил изменить чужое помещение'; end if;
  begin
    insert into public.project_rooms(user_id,project_id,data) values(owner_id,project_id,payload);
    raise exception 'RLS позволил создать чужое помещение';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  delete from public.projects where id=project_id;
  if exists(select 1 from public.project_rooms where id=room_id) then
    raise exception 'Помещение осталось после удаления объекта';
  end if;
  raise notice 'Помещения: CRUD, ревизии, конфликт, обязательные поля, RLS, каскад проверены';
end $$;
rollback;
