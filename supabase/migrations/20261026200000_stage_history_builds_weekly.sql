-- Command center v3: stage history, Site Builder projects, weekly numbers, crew roster.
-- Safe to re-run.

-- Stage history: every stage a lead enters, stamped by a trigger, so weekly numbers need no agent.
create table if not exists ops.lead_events (
  id bigserial primary key,
  lead_id text not null references ops.leads(id) on delete cascade,
  stage text not null,
  at timestamptz not null default now()
);
create index if not exists lead_events_at on ops.lead_events (at);
create index if not exists lead_events_lead on ops.lead_events (lead_id);

-- Site Builder projects: one per won client.
create table if not exists ops.builds (
  id text primary key,
  lead_id text not null unique references ops.leads(id),
  business text not null,
  package text not null default '',
  status text not null default 'Waiting on intake'
    check (status in ('Waiting on intake', 'Building', 'Preview ready', 'Changes requested', 'Launched')),
  intake text not null default '',
  preview_url text not null default '',
  live_domain text not null default '',
  checklist text not null default '',
  you_action text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists builds_touch on ops.builds;
create trigger builds_touch before update on ops.builds for each row execute function ops.touch_updated();

-- Log stage changes, and open a build when a lead is won.
create or replace function ops.log_stage() returns trigger
language plpgsql set search_path to '' as $$
begin
  if tg_op = 'INSERT' or new.stage is distinct from old.stage then
    insert into ops.lead_events (lead_id, stage) values (new.id, new.stage);
    if new.stage = 'Won' then
      insert into ops.builds (id, lead_id, business, package, you_action)
      values ('B' || new.id, new.id, new.business, new.package,
              'Send ' || new.business || ' the intake list: logo, photos, services, hours, service area')
      on conflict (lead_id) do nothing;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists leads_stage_log on ops.leads;
create trigger leads_stage_log after insert or update of stage on ops.leads
  for each row execute function ops.log_stage();

insert into ops.lead_events (lead_id, stage, at)
select l.id, l.stage, l.created_at from ops.leads l
where not exists (select 1 from ops.lead_events e where e.lead_id = l.id);

-- Last 8 weeks (Monday start, Central time).
create or replace view ops.weekly_stats as
with weeks as (
  select generate_series(
    date_trunc('week', (now() at time zone 'America/Chicago')::date) - interval '7 weeks',
    date_trunc('week', (now() at time zone 'America/Chicago')::date),
    interval '1 week')::date as week
),
ev as (
  select e.lead_id, e.stage, date_trunc('week', e.at at time zone 'America/Chicago')::date as week
  from ops.lead_events e
)
select w.week,
  (select count(*) from ops.leads l
     where date_trunc('week', l.created_at at time zone 'America/Chicago')::date = w.week) as found,
  (select count(*) from ops.leads l where date_trunc('week', l.first_contact)::date = w.week) as contacted,
  (select count(distinct lead_id) from ev where ev.week = w.week and ev.stage = 'Mockup ready') as mockups,
  (select count(distinct lead_id) from ev where ev.week = w.week and ev.stage = 'Replied') as replied,
  (select count(distinct lead_id) from ev where ev.week = w.week and ev.stage = 'Won') as won,
  (select coalesce(sum(l.deal_value), 0) from ops.leads l
     where l.id in (select lead_id from ev where ev.week = w.week and ev.stage = 'Won')) as won_value
from weeks w
order by w.week;

-- Crew roster: the Site Builder, and the Contact Finder now runs inside the Sales Agent.
insert into ops.agents (id, ord, name, role, status, schedule, hands_to, uses_ai, last_run, next_run, last_result)
values ('site', 6, 'Site Builder',
        'Turns a won client''s mockup and intake details into the full website, deploys a preview, and writes the launch checklist.',
        'Live', 'Tue and Thu 8:33 AM, with the Mockup Builder', 'You (review with the client)', true,
        (now() at time zone 'America/Chicago')::date, 'Tue 8:33 AM', 'Set up. Starts building as soon as a deal is won.')
on conflict (id) do update set ord = excluded.ord, name = excluded.name, role = excluded.role,
  schedule = excluded.schedule, hands_to = excluded.hands_to;
update ops.agents set ord = 7 where id = 'content';
update ops.agents set
  role = 'Searches the web for each new lead: phone, email, Facebook, and whether they really have a website. Rates any site it finds.',
  schedule = 'Mon, Wed, Fri 9:17 AM, with the Sales Agent'
where id = 'finder';

-- Planner: add build tasks, and give Tue/Thu agents room over the weekend.
create or replace function ops.build_todos()
 returns text
 language plpgsql
 set search_path to ''
as $function$
declare today date := (now() at time zone 'America/Chicago')::date; n int;
begin
  update ops.leads set stage = 'Lost', you_action = '', next_followup = null
  where stage = 'Contacted' and touches >= 4 and last_contact < today - 7;

  delete from ops.todos;
  insert into ops.todos (type, item, who, agent, priority)
  select case when you_action ilike 'call%' then 'Call'
              when you_action ilike 'message%' then 'Message'
              when you_action ilike '%replied%' or you_action ilike '%reply%' then 'Reply'
              when you_action ilike 'don''t%' or you_action ilike '%delete%' then 'Fix'
              when you_action ilike '%start the build%' then 'Build'
              else 'Send' end,
         you_action, business, 'Sales Agent',
         case when stage in ('Replied','Proposal sent','Won') or you_action ilike 'don''t%' then 1 else 2 end
  from ops.leads where you_action <> '' and stage not in ('Lost','Opted out');

  insert into ops.todos (type, item, who, agent, priority)
  select 'Build', you_action, business, 'Site Builder', 1
  from ops.builds where you_action <> '' and status <> 'Launched';

  insert into ops.todos (type, item, who, agent, priority)
  select 'Post', to_char(date, 'Dy Mon FMDD') || ': ' || hook, platforms, 'Content Agent', 3
  from ops.posts where date between today and today + 1;

  insert into ops.todos (type, item, who, agent, priority)
  select 'Fix', name || ' has not run since ' || coalesce(to_char(last_run, 'Mon FMDD'), 'it was set up') || '. Check its scheduled task.', name, 'Daily Planner', 1
  from ops.agents where uses_ai and status = 'Live' and id in ('finder','sales','builder','site','content')
    and coalesce(last_run, today - 30) < today - case when id = 'content' then 8 when id in ('builder','site') then 5 when id = 'finder' then 4 else 3 end;

  get diagnostics n = row_count;
  update ops.agents set last_run = today, status = 'Live',
    last_result = (select count(*) from ops.todos) || ' items on your list. ' ||
                  (select count(*) from ops.leads where stage = 'Contacted' and next_followup <= today) || ' follow-ups due for the Sales Agent.'
  where id = 'planner';
  return (select count(*) from ops.todos)::text;
end $function$;
