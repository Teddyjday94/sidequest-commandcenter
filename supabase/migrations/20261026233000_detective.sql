-- The Detective: one research file per lead, filled from public business sources, read by the
-- Sales Agent (greeting, angles), the Mockup Builder and the Site Builder (services, photos, colors).
-- Safe to re-run.

create table if not exists ops.dossiers (
  lead_id text primary key references ops.leads(id) on delete cascade,
  owner_name text not null default '',
  owner_source text not null default '',
  founded text not null default '',
  services text not null default '',
  service_area text not null default '',
  hours text not null default '',
  story text not null default '',
  credentials text not null default '',
  brand_colors text not null default '',
  logo_url text not null default '',
  photos jsonb not null default '[]'::jsonb,
  reviews text not null default '',
  social text not null default '',
  booking text not null default '',
  competitors text not null default '',
  pitch_angles text not null default '',
  sources jsonb not null default '[]'::jsonb,
  confidence text not null default '',
  researched_at timestamptz not null default now(),
  constraint photos_is_array check (jsonb_typeof(photos) = 'array'),
  constraint sources_is_array check (jsonb_typeof(sources) = 'array')
);

insert into ops.agents (id, ord, name, role, status, schedule, hands_to, uses_ai, last_run, next_run, last_result)
values ('detective', 4, 'Detective',
        'Digs into each hot lead before it is pitched or built: owner name as the business publishes it, how long they have been around, services, service area, their own photos and logo, review themes, nearby rivals with websites, and the best pitch angles.',
        'Live', 'Tue and Thu 8:33 AM, before the Mockup Builder', 'Sales Agent, Mockup Builder, Site Builder', true,
        (now() at time zone 'America/Chicago')::date, 'Tue 8:33 AM', 'Set up. First case files on Tuesday.')
on conflict (id) do update set ord = excluded.ord, name = excluded.name, role = excluded.role,
  schedule = excluded.schedule, hands_to = excluded.hands_to;
update ops.agents set ord = 5 where id = 'sales';
update ops.agents set ord = 6 where id = 'builder';
update ops.agents set ord = 7 where id = 'site';
update ops.agents set ord = 8 where id = 'content';

-- Planner: watch the Detective like the other Tue/Thu agents.
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
  from ops.agents where uses_ai and status = 'Live' and id in ('finder','detective','sales','builder','site','content')
    and coalesce(last_run, today - 30) < today - case when id = 'content' then 8 when id in ('builder','site','detective') then 5 when id = 'finder' then 4 else 3 end;

  get diagnostics n = row_count;
  update ops.agents set last_run = today, status = 'Live',
    last_result = (select count(*) from ops.todos) || ' items on your list. ' ||
                  (select count(*) from ops.leads where stage = 'Contacted' and next_followup <= today) || ' follow-ups due for the Sales Agent.'
  where id = 'planner';
  return (select count(*) from ops.todos)::text;
end $function$;
