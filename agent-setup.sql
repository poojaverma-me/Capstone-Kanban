-- Board Agent setup. Run once AFTER schema.sql:
-- Supabase dashboard → SQL Editor → New query → paste → Run.
-- The last result row is your agent token. Copy it — it is shown only once.
--
-- What this adds:
--   • agent_runs      a log of every document/request the agent processed
--   • members.email / members.aliases / members.role   so the agent can match owners
--   • tasks.source_run_id   which agent run created a task
--   • board_agent     a restricted database role: read/write on the board tables only, no schema changes
--   • agent_sql(token, query)   lets the agent page run one SQL statement as board_agent, if the token is valid

-- ── 1. Extra columns the agent uses ─────────────────────────────────────────
alter table public.members add column if not exists email   text;
alter table public.members add column if not exists aliases text[] not null default '{}';
alter table public.members add column if not exists role    text   not null default '';

-- ── 2. Run log ──────────────────────────────────────────────────────────────
create table if not exists public.agent_runs (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  source_title  text not null default '',
  submitted_by  text not null default '',
  source_text   text not null default '',
  source_hash   text,
  status        text not null default 'in_progress'
                check (status in ('in_progress', 'applied', 'needs_clarification', 'no_changes', 'failed')),
  summary       text not null default '',
  questions     text not null default '',
  statements    text[] not null default '{}',
  result        jsonb
);
create index if not exists agent_runs_hash_idx on public.agent_runs(source_hash);

drop trigger if exists agent_runs_touch on public.agent_runs;
create trigger agent_runs_touch before update on public.agent_runs
for each row execute function public.touch_updated_at();

alter table public.tasks add column if not exists source_run_id uuid references public.agent_runs(id) on delete set null;

alter table public.agent_runs enable row level security;
drop policy if exists "team read" on public.agent_runs;
create policy "team read" on public.agent_runs for select to anon, authenticated using (true);

-- ── 3. Restricted role the agent's SQL runs as ──────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'board_agent') then
    create role board_agent nologin;
  end if;
end $$;
grant board_agent to postgres;

grant usage on schema public to board_agent;
grant select, insert, update, delete on public.members, public.tasks, public.task_assignees, public.agent_runs to board_agent;

drop policy if exists "agent access" on public.members;
drop policy if exists "agent access" on public.tasks;
drop policy if exists "agent access" on public.task_assignees;
drop policy if exists "agent access" on public.agent_runs;
create policy "agent access" on public.members        for all to board_agent using (true) with check (true);
create policy "agent access" on public.tasks          for all to board_agent using (true) with check (true);
create policy "agent access" on public.task_assignees for all to board_agent using (true) with check (true);
create policy "agent access" on public.agent_runs     for all to board_agent using (true) with check (true);

-- ── 4. Agent tokens (only hashes are stored) ────────────────────────────────
create table if not exists public.agent_tokens (
  token_hash  text primary key,
  label       text not null default 'browser agent',
  created_at  timestamptz not null default now()
);
alter table public.agent_tokens enable row level security; -- no policies: nobody can read it through the API
revoke all on public.agent_tokens from anon, authenticated;

create or replace function public.agent_token_ok(token text) returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.agent_tokens
    where token_hash = encode(sha256(convert_to(coalesce(token, ''), 'UTF8')), 'hex')
  )
$$;
revoke all on function public.agent_token_ok(text) from public, anon, authenticated;
grant execute on function public.agent_token_ok(text) to board_agent;

create or replace function public.agent_new_token(label text default 'browser agent') returns text
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  t text := 'agt_' || replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  insert into public.agent_tokens (token_hash, label) values (encode(sha256(convert_to(t, 'UTF8')), 'hex'), label);
  return t;
end $$;
revoke all on function public.agent_new_token(text) from public, anon, authenticated;

-- ── 5. agent_sql: run one statement as board_agent ──────────────────────────
-- Returns {"kind": "rows" | "returning" | "command", "row_count": n, "rows": [...] | null}
create or replace function public.agent_sql(token text, query text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  q    text := regexp_replace(btrim(coalesce(query, '')), ';\s*$', '');
  rows jsonb;
  n    bigint;
begin
  if not public.agent_token_ok(token) then
    raise exception 'Invalid agent token' using errcode = '28000';
  end if;
  if q = '' then
    raise exception 'Empty query';
  end if;
  perform set_config('statement_timeout', '15s', true);

  if q ~* '^(select|values|table)\M' or (q ~* '^with\M' and q !~* '\m(insert|update|delete)\M') then
    execute format('select coalesce(jsonb_agg(_r), ''[]''::jsonb) from (%s) _r', q) into rows;
    return jsonb_build_object('kind', 'rows', 'row_count', jsonb_array_length(rows), 'rows', rows);
  elsif q ~* '^(insert|update|delete)\M' and q ~* '\mreturning\M' then
    execute format('with _r as (%s) select coalesce(jsonb_agg(_r), ''[]''::jsonb) from _r', q) into rows;
    return jsonb_build_object('kind', 'returning', 'row_count', jsonb_array_length(rows), 'rows', rows);
  else
    execute q;
    get diagnostics n = row_count;
    return jsonb_build_object('kind', 'command', 'row_count', n, 'rows', null);
  end if;
end $$;

-- The function runs with board_agent's limited rights, not the owner's.
-- (Changing the owner needs CREATE on the schema for a moment; it is revoked right after.)
grant create on schema public to board_agent;
alter function public.agent_sql(text, text) owner to board_agent;
revoke create on schema public from board_agent;

revoke all on function public.agent_sql(text, text) from public;
grant execute on function public.agent_sql(text, text) to anon, authenticated;

-- Make PostgREST pick up the new function and columns right away
notify pgrst, 'reload schema';

-- ── 6. Your agent token ─────────────────────────────────────────────────────
-- Paste it into agent.html once. To revoke every token later:  delete from public.agent_tokens;
-- To make a new one:  select public.agent_new_token('label');
select public.agent_new_token('browser agent') as "agent token — copy it now, it is shown only once";
