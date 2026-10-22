-- Выполнил проверки в транзакции: тестовые объекты и операции не сохраняются.
begin;
do $$
declare
  owner_id uuid;
  first_project uuid := gen_random_uuid();
  second_project uuid := gen_random_uuid();
  first_transaction uuid := gen_random_uuid();
begin
  select id into owner_id from auth.users order by created_at limit 1;
  if owner_id is null then raise exception 'Для проверки нужен существующий пользователь'; end if;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  execute 'set local role authenticated';

  insert into public.projects(id, user_id, title)
  values (first_project, owner_id, 'Проверка плательщиков 1'),
         (second_project, owner_id, 'Проверка плательщиков 2');

  insert into public.project_transactions(id, user_id, project_id, transaction_type, category, title, amount, payer_name)
  values (first_transaction, owner_id, first_project, 'expense', 'Материалы', 'Кирпич', 100, '  Джамал  ');
  insert into public.project_transactions(user_id, project_id, transaction_type, category, title, amount, payer_name)
  values (owner_id, first_project, 'expense', 'Доставка', 'Доставка кирпича', 50, 'джамал'),
         (owner_id, second_project, 'expense', 'Материалы', 'Доски', 200, 'Илья');

  if (select count(*) from public.project_payers where project_id = first_project) <> 1 then
    raise exception 'Имя с разным регистром создало дубликат';
  end if;
  if (select name from public.project_payers where project_id = first_project) <> 'Джамал' then
    raise exception 'Имя не нормализовано';
  end if;
  if (select payer_name from public.project_transactions where id = first_transaction) <> 'Джамал' then
    raise exception 'В операции не сохранено имя';
  end if;
  if exists (select 1 from public.project_payers where project_id = second_project and name = 'Джамал') then
    raise exception 'Плательщик попал в другой объект';
  end if;

  delete from public.project_transactions where project_id = first_project;
  if (select count(*) from public.project_payers where project_id = first_project) <> 1 then
    raise exception 'Плательщик забыт после удаления операции';
  end if;

  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  if exists (select 1 from public.project_payers where project_id in (first_project, second_project)) then
    raise exception 'RLS позволил прочитать чужих плательщиков';
  end if;
  begin
    insert into public.project_payers(user_id, project_id, name)
    values (owner_id, first_project, 'Чужой');
    raise exception 'RLS позволил записать чужого плательщика';
  exception when insufficient_privilege then
    null;
  end;
  raise notice 'Проверены: нормализация, сохранение, изоляция объектов, память после удаления, RLS чтения и записи';
end;
$$;
rollback;
