-- The crew learns from results.
-- 1. pitch_angle: the Sales Agent tags each email with the angle it led with, so results can be compared by angle.
-- 2. ops.lead_outcomes / ops.scorecard: who was contacted, who replied, who was won, grouped by niche, town,
--    source, angle and heat. The Sunday Strategist reads it and writes ops.settings 'lessons', which the
--    Sales Agent, Detective and Scout read before they work.
-- 3. ops.lead_priority(lead) and ops.lead_next_move(lead): one "next best move" score per lead, computed live,
--    used to sort Lead Desk and HQ. No Claude run needed.
-- Safe to re-run.

alter table ops.leads add column if not exists pitch_angle text not null default '';

create or replace view ops.lead_outcomes as
select l.id, l.business, l.niche, l.area, l.found_on, l.heat, l.score,
       coalesce(nullif(l.pitch_angle, ''), 'untagged') as pitch_angle,
       (l.touches > 0 or exists (select 1 from ops.lead_events e where e.lead_id = l.id and e.stage = 'Contacted')) as contacted,
       (l.stage in ('Replied', 'Proposal sent', 'Won') or exists (select 1 from ops.lead_events e where e.lead_id = l.id and e.stage in ('Replied', 'Proposal sent', 'Won'))) as replied,
       (l.stage = 'Won') as won,
       l.touches, l.stage
  from ops.leads l;

create or replace view ops.scorecard as
with o as (select * from ops.lead_outcomes),
dims as (
  select 'niche' as dimension, coalesce(nullif(niche, ''), 'unknown') as value, contacted, replied, won from o
  union all select 'town', coalesce(nullif(area, ''), 'unknown'), contacted, replied, won from o
  union all select 'source', coalesce(nullif(found_on, ''), 'unknown'), contacted, replied, won from o
  union all select 'angle', pitch_angle, contacted, replied, won from o
  union all select 'heat', coalesce(nullif(heat, ''), 'unknown'), contacted, replied, won from o
)
select dimension, value,
       count(*) as leads,
       count(*) filter (where contacted) as contacted,
       count(*) filter (where replied) as replied,
       count(*) filter (where won) as won,
       case when count(*) filter (where contacted) > 0
            then round(100.0 * count(*) filter (where replied) / count(*) filter (where contacted)) end as reply_rate_pct
  from dims
 group by dimension, value;

-- How likely similar leads are to reply: the niche's reply rate once 5 or more have been contacted, else null.
create or replace function ops.niche_reply_rate(p_niche text)
returns numeric
language sql stable
set search_path to ''
as $$
  select case when count(*) filter (where contacted) >= 5
              then count(*) filter (where replied)::numeric / count(*) filter (where contacted) end
    from ops.lead_outcomes where niche = p_niche;
$$;

create or replace function ops.lead_priority(l ops.leads)
returns integer
language sql stable
set search_path to ''
as $$
  select case when l.stage in ('Won', 'Lost', 'Opted out') then -1 else greatest(0, round(
      coalesce(l.score, 50) * 0.5
    + case l.stage
        when 'Replied' then 60
        when 'Proposal sent' then 40
        when 'Mockup ready' then case when l.touches = 0 then 25 else 0 end
        when 'Contacted' then case when l.next_followup is not null and l.next_followup <= (now() at time zone 'America/Chicago')::date then 35 else -20 end
        when 'Audited' then 10
        else 0 end
    + case when l.email <> '' then 15 when l.phone <> '' then 10 when l.facebook <> '' then 5 else -30 end
    + case when l.draft_id <> '' and l.touches = 0 then 10 when l.email_text <> '' then 5 else 0 end
    + case when l.created_at > now() - interval '7 days' then 5 else 0 end
    + coalesce(40 * ops.niche_reply_rate(l.niche), 0)
  ))::integer end;
$$;

create or replace function ops.lead_next_move(l ops.leads)
returns text
language sql stable
set search_path to ''
as $$
  select case
    when l.stage in ('Won', 'Lost', 'Opted out') then ''
    when l.stage = 'Replied' then 'Answer their reply (draft in Gmail)'
    when l.stage = 'Proposal sent' then 'Check in on the proposal'
    when l.stage = 'Contacted' and l.next_followup is not null and l.next_followup <= (now() at time zone 'America/Chicago')::date
      then 'Send follow-up ' || (l.touches + 1) || ' (draft in Gmail)'
    when l.stage = 'Contacted' then 'Wait for the follow-up date'
    when l.draft_id <> '' then 'Send the Gmail draft'
    when l.email <> '' and l.email_text <> '' then 'Make the Gmail draft and send it'
    when l.phone <> '' then 'Call them (script on the board)'
    when l.facebook <> '' then 'Message them on Facebook'
    else 'Find a way to reach them' end;
$$;

-- The Strategist's notes, read by the agents. Starts empty until the first Friday run.
insert into ops.settings (key, value) values ('lessons', '') on conflict (key) do nothing;
insert into ops.settings (key, value) values ('lessons_updated', '') on conflict (key) do nothing;

-- New crew members for the dashboard's Crew tab.
insert into ops.agents (id, ord, name, role, status, schedule, next_run, uses_ai)
values ('strategist', 9, 'Strategist', 'Reads the week''s results (who replied, by niche, town, source and pitch angle) and writes the short "What''s working" notes every other agent reads before it works.', 'Live', 'Sundays 5:43 PM (with the Content Agent)', 'Sun 5:43 PM', true),
       ('replies', 10, 'Reply Watcher', 'A quick midday pass on weekdays that only looks for new replies and drafts answers in Gmail, so nobody waits until the next morning.', 'Live', 'Weekdays 1:17 PM (with the Sales Agent)', 'next weekday 1:17 PM', true)
on conflict (id) do update set name = excluded.name, role = excluded.role, schedule = excluded.schedule, next_run = excluded.next_run;
