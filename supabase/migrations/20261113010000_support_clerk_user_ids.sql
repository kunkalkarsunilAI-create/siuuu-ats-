-- Clerk user ids look like "user_2abc…", not UUIDs: store the JWT subject as text.
do $$ declare t text; begin
  foreach t in array array['jobs','candidates','applications','config'] loop
    execute format('alter table public.%I alter column updated_by drop default', t);
    execute format('alter table public.%I alter column updated_by type text using updated_by::text', t);
    execute format('alter table public.%I alter column updated_by set default (auth.jwt()->>''sub'')', t);
  end loop;
end $$;
alter table public.audit_log alter column actor drop default;
alter table public.audit_log alter column actor type text using actor::text;
alter table public.audit_log alter column actor set default (auth.jwt()->>'sub');

create or replace function public.touch_and_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('INSERT','UPDATE') then
    new.updated_at := now(); new.updated_by := auth.jwt()->>'sub';
    insert into public.audit_log(table_name, record_id, action) values (tg_table_name, new.id, lower(tg_op));
    return new;
  else
    insert into public.audit_log(table_name, record_id, action) values (tg_table_name, old.id, 'delete');
    return old;
  end if;
end $$;
revoke execute on function public.touch_and_audit() from public, anon, authenticated;
