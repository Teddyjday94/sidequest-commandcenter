-- Lead Desk: the actions Thomas takes by hand, as one checked function the Lead Desk page calls.
-- Safe to re-run.

alter table ops.leads add column if not exists mockup_requested boolean not null default false;

create or replace function ops.lead_action(p_lead text, p_action text, p_package text default null)
returns text
language plpgsql
set search_path to ''
as $$
declare
  today date := (now() at time zone 'America/Chicago')::date;
  l ops.leads%rowtype;
  how text;
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'bad_lead_id';
  end if;
  if p_action not in ('mockup', 'emailed', 'called', 'messaged', 'replied', 'won', 'lost', 'optout', 'reopen') then
    raise exception using errcode = '22023', message = 'bad_action';
  end if;

  select * into l from ops.leads where id = p_lead for update;
  if not found then
    raise exception using errcode = '22023', message = 'lead_not_found';
  end if;
  if l.stage = 'Opted out' then
    raise exception using errcode = '55000', message = 'lead_opted_out';
  end if;
  if p_action = 'reopen' and l.stage <> 'Lost' then
    raise exception using errcode = '22023', message = 'only_lost_reopens';
  end if;

  if p_action = 'mockup' then
    update ops.leads set mockup_requested = true,
      next_step = 'Mockup requested, the Mockup Builder makes it next Tue or Thu'
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', 'Asked for a mockup for ' || l.business);

  elsif p_action in ('emailed', 'called', 'messaged') then
    how := case p_action when 'emailed' then 'Emailed' when 'called' then 'Called' else 'Messaged on Facebook' end;
    update ops.leads set
      stage = case when stage in ('New', 'Audited', 'Mockup ready') then 'Contacted' else stage end,
      first_contact = coalesce(first_contact, today),
      last_contact = today,
      touches = touches + 1,
      next_followup = today + case when touches + 1 <= 1 then 3 when touches + 1 = 2 then 4 else 7 end,
      next_step = how || ' on ' || to_char(today, 'Mon FMDD') || ', follow-up due ' ||
        to_char(today + case when touches + 1 <= 1 then 3 when touches + 1 = 2 then 4 else 7 end, 'Mon FMDD'),
      you_action = ''
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', how || ' ' || l.business);

  elsif p_action = 'replied' then
    update ops.leads set stage = 'Replied', last_contact = today, next_followup = null,
      next_step = 'They replied. The Sales Agent drafts an answer next run if it came by email.'
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', l.business || ' replied');

  elsif p_action = 'won' then
    if p_package not in ('Starter', 'Full') then
      raise exception using errcode = '22023', message = 'bad_package';
    end if;
    update ops.leads set stage = 'Won', package = p_package,
      deal_value = case p_package when 'Starter' then 600 else 800 end,
      next_followup = null, next_step = 'Won. The Site Builder takes it from here.',
      you_action = ''
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', 'Won ' || l.business || ' (' || p_package || ')');

  elsif p_action = 'lost' then
    update ops.leads set stage = 'Lost', next_followup = null, you_action = '', next_step = 'Not interested'
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', 'Marked ' || l.business || ' not interested');

  elsif p_action = 'optout' then
    update ops.leads set stage = 'Opted out', next_followup = null, you_action = '', next_step = 'Asked not to be contacted'
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', l.business || ' opted out');

  elsif p_action = 'reopen' then
    update ops.leads set stage = 'Audited', next_followup = null, next_step = 'Reopened by you'
    where id = p_lead;
    insert into ops.activity (agent, action) values ('you', 'Reopened ' || l.business);
  end if;

  perform ops.build_todos();
  return p_action;
end $$;
