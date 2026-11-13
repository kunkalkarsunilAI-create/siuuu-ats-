-- Meridian ATS: core schema, access control and audit log.
-- Applied to Supabase project "meridian-ats" (bsbpcbgngtlqqrqtabou).

-- Team allowlist and roles
create table public.team_members (
  email text primary key check (email = lower(email)),
  name text,
  role text not null default 'recruiter' check (role in ('admin','recruiter','viewer')),
  created_at timestamptz not null default now()
);

-- Document tables (one JSON document per record, mirrors the app's data model)
create table public.jobs (
  id text primary key, data jsonb not null,
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid()
);
create table public.candidates (
  id text primary key, data jsonb not null,
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid()
);
create table public.applications (
  id text primary key, data jsonb not null,
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid()
);
create table public.config (
  id text primary key, data jsonb not null,
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid()
);
create index candidates_phone_idx on public.candidates ((right(regexp_replace(data->>'phone','\D','','g'),10)));
create index applications_job_idx on public.applications ((data->>'jobId'));
create index applications_cand_idx on public.applications ((data->>'candidateId'));

-- Audit log: who changed what. No personal data is stored, so it survives DPDP erasure.
create table public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor uuid default auth.uid(),
  actor_email text default (auth.jwt()->>'email'),
  table_name text not null, record_id text not null, action text not null
);

-- Role helpers
create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.team_members where email = lower(auth.jwt()->>'email')
$$;
create or replace function public.can_read() returns boolean
language sql stable set search_path = public as $$ select public.my_role() is not null $$;
create or replace function public.can_write() returns boolean
language sql stable set search_path = public as $$ select public.my_role() in ('admin','recruiter') $$;
create or replace function public.is_admin() returns boolean
language sql stable set search_path = public as $$ select public.my_role() = 'admin' $$;

-- Lets the sign-up screen check an email is invited before creating an account
create or replace function public.is_invited(p_email text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.team_members where email = lower(trim(p_email)))
$$;
grant execute on function public.is_invited(text) to anon, authenticated;

-- Block sign-ups from emails that are not invited
create or replace function public.enforce_invite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.team_members where email = lower(new.email)) then
    raise exception 'This email has not been invited to Meridian ATS';
  end if;
  return new;
end $$;
create trigger enforce_invite_before_signup before insert on auth.users
  for each row execute function public.enforce_invite();

-- updated_at + audit triggers
create or replace function public.touch_and_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op in ('INSERT','UPDATE') then
    new.updated_at := now(); new.updated_by := auth.uid();
    insert into public.audit_log(table_name, record_id, action) values (tg_table_name, new.id, lower(tg_op));
    return new;
  else
    insert into public.audit_log(table_name, record_id, action) values (tg_table_name, old.id, 'delete');
    return old;
  end if;
end $$;
do $$ declare t text; begin
  foreach t in array array['jobs','candidates','applications','config'] loop
    execute format('create trigger %I_touch before insert or update on public.%I for each row execute function public.touch_and_audit()', t, t);
    execute format('create trigger %I_audit_del after delete on public.%I for each row execute function public.touch_and_audit()', t, t);
  end loop;
end $$;

-- Function privileges
revoke execute on function public.enforce_invite() from public, anon, authenticated;
revoke execute on function public.touch_and_audit() from public, anon, authenticated;
revoke execute on function public.my_role() from public, anon;
revoke execute on function public.can_read() from public, anon;
revoke execute on function public.can_write() from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.my_role(), public.can_read(), public.can_write(), public.is_admin() to authenticated;

-- Row level security
alter table public.team_members enable row level security;
alter table public.jobs enable row level security;
alter table public.candidates enable row level security;
alter table public.applications enable row level security;
alter table public.config enable row level security;
alter table public.audit_log enable row level security;

do $$ declare t text; begin
  foreach t in array array['jobs','candidates','applications','config'] loop
    execute format('create policy "team reads" on public.%I for select to authenticated using (public.can_read())', t);
    execute format('create policy "writers insert" on public.%I for insert to authenticated with check (public.can_write())', t);
    execute format('create policy "writers update" on public.%I for update to authenticated using (public.can_write()) with check (public.can_write())', t);
    execute format('create policy "writers delete" on public.%I for delete to authenticated using (public.can_write())', t);
  end loop;
end $$;

create policy "team reads members" on public.team_members for select to authenticated using (public.can_read());
create policy "admin manages members" on public.team_members for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin reads audit" on public.audit_log for select to authenticated using (public.is_admin());

-- Live updates
alter publication supabase_realtime add table public.jobs, public.candidates, public.applications, public.config;
