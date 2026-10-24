-- Sidequest agents: private "ops" schema inside the Side Quest Client Portal project.
-- Not exposed to the API (no grants to anon/authenticated). RLS on, no policies.
create schema if not exists ops;
revoke all on schema ops from public, anon, authenticated;

create table if not exists ops.leads (
  id text primary key,
  business text not null,
  niche text, area text, found_on text, profile_url text, rating text,
  website text default 'Not confirmed (HomeAdvisor only)',
  email text default '', phone text default '', facebook text default '', contact text default '',
  score int default 50, heat text default 'Warm', stage text default 'New',
  hook text default '', next_step text default '', you_action text default '',
  mockup_url text default '', call_script text default '', dm_text text default '',
  draft_id text default '', proposal_draft_id text default '', invoice_id text default '',
  package text default '', deal_value numeric default 0,
  first_contact date, last_contact date, touches int default 0, next_followup date,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create unique index if not exists leads_business_uq on ops.leads (lower(business));

create table if not exists ops.agents (
  id text primary key, ord int, name text, role text, status text, schedule text,
  next_run text, last_run date, last_result text, hands_to text, uses_ai boolean default true
);
create table if not exists ops.activity (id bigserial primary key, at timestamptz default now(), agent text, action text);
create table if not exists ops.posts (
  id text primary key, date date, platforms text, pillar text, format text, hook text,
  idea text, caption text, cta text, asset text, status text
);
create table if not exists ops.todos (
  id bigserial primary key, type text, item text, who text, agent text, priority int default 2,
  created_on date default (now() at time zone 'America/Chicago')::date
);
create table if not exists ops.settings (key text primary key, value text);
create table if not exists ops.clients (name text primary key);
create table if not exists ops.near_cities (city text primary key);
create table if not exists ops.scout_targets (
  id serial primary key, city text not null, category text not null, niche text not null,
  near boolean default true, enabled boolean default true, last_run timestamptz, last_status int,
  unique (city, category)
);

alter table ops.leads enable row level security;
alter table ops.agents enable row level security;
alter table ops.activity enable row level security;
alter table ops.posts enable row level security;
alter table ops.todos enable row level security;
alter table ops.settings enable row level security;
alter table ops.clients enable row level security;
alter table ops.near_cities enable row level security;
alter table ops.scout_targets enable row level security;
