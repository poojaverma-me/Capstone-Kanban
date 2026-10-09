-- Kanban board schema for Supabase.
-- Run once: Supabase dashboard → SQL Editor → New query → paste → Run.

-- Team members
create table if not exists public.members (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  color       text not null default '#007aff',
  created_at  timestamptz not null default now()
);

-- Tasks (cards on the board)
create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  status      text not null default 'todo' check (status in ('todo', 'in_progress', 'done')),
  priority    text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  due_date    date,
  position    double precision not null default 0, -- order inside a column
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Many-to-many: a task can have several assignees, a member can have several tasks
create table if not exists public.task_assignees (
  task_id    uuid not null references public.tasks(id) on delete cascade,
  member_id  uuid not null references public.members(id) on delete cascade,
  primary key (task_id, member_id)
);

create index if not exists task_assignees_member_idx on public.task_assignees(member_id);
create index if not exists tasks_status_position_idx on public.tasks(status, position);

-- Keep updated_at fresh
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists tasks_touch on public.tasks;
create trigger tasks_touch before update on public.tasks
for each row execute function public.touch_updated_at();

-- Row Level Security.
-- These policies let anyone who has your project URL + publishable (anon) key read and edit the board.
-- That suits a class project shared with your team; don't put private data in it.
alter table public.members        enable row level security;
alter table public.tasks          enable row level security;
alter table public.task_assignees enable row level security;

drop policy if exists "team access" on public.members;
drop policy if exists "team access" on public.tasks;
drop policy if exists "team access" on public.task_assignees;
create policy "team access" on public.members        for all to anon, authenticated using (true) with check (true);
create policy "team access" on public.tasks          for all to anon, authenticated using (true) with check (true);
create policy "team access" on public.task_assignees for all to anon, authenticated using (true) with check (true);

-- Live updates: teammates see each other's changes instantly
do $$
begin
  begin alter publication supabase_realtime add table public.members;        exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.tasks;          exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.task_assignees; exception when duplicate_object then null; end;
end $$;

-- Starter team (rename or delete from the app's Team button)
insert into public.members (name, color)
select * from (values
  ('Pooja',  '#007aff'),
  ('Arjun',  '#ff9500'),
  ('Sofia',  '#34c759'),
  ('Daniel', '#af52de'),
  ('Maya',   '#ff2d55')
) as v(name, color)
where not exists (select 1 from public.members);
