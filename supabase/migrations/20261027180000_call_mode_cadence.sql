-- Call Mode and a multi-channel follow-up plan.
-- Most leads have a phone and no email, so outreach runs on calls and texts:
--   * The Sales Agent writes sms_text (first text), sms_followup (later nudge) and voicemail for every lead with a phone.
--   * ops.lead_touch(lead, channel, result) records what Thomas did in Lead Desk's Call Mode and schedules the
--     next touch (next_channel + next_followup) on the plan: call, then text, then email or Facebook, then call,
--     then a last text. Two missed calls in a row turn into a text.
--   * ops.touches logs every touch so the Strategist can compare channels.
-- Safe to re-run.

alter table ops.leads add column if not exists sms_text text not null default '';
alter table ops.leads add column if not exists sms_followup text not null default '';
alter table ops.leads add column if not exists voicemail text not null default '';
alter table ops.leads add column if not exists next_channel text not null default '';
alter table ops.leads add column if not exists call_attempts integer not null default 0;

create table if not exists ops.touches (
  id bigint generated always as identity primary key,
  lead_id text not null references ops.leads (id) on delete cascade,
  channel text not null,      -- call, text, facebook, email
  result text not null,       -- no_answer, voicemail, talked, interested, not_interested, wrong_number, sent
  at timestamptz not null default now()
);
alter table ops.touches enable row level security;
create index if not exists touches_lead_idx on ops.touches (lead_id, at desc);

-- The next channel on the plan after n touches, skipping channels this lead can't be reached on.
create or replace function ops.plan_channel(p_touches int, p_phone text, p_email text, p_facebook text)
returns text
language plpgsql immutable
set search_path to ''
as $$
declare want text[]; c text;
begin
  want := case p_touches
    when 0 then array['call', 'email', 'facebook', 'text']
    when 1 then array['text', 'email', 'facebook', 'call']
    when 2 then array['email', 'facebook', 'call', 'text']
    when 3 then array['call', 'text', 'email', 'facebook']
    when 4 then array['text', 'facebook', 'email', 'call']
    else array[]::text[] end;
  foreach c in array want loop
    if (c in ('call', 'text') and coalesce(p_phone, '') <> '') or (c = 'email' and coalesce(p_email, '') <> '') or (c = 'facebook' and coalesce(p_facebook, '') <> '') then
      return c;
    end if;
  end loop;
  return '';
end $$;

create or replace function ops.lead_touch(p_lead text, p_channel text, p_result text)
returns text
language plpgsql
set search_path to ''
as $$
declare
  today date := (now() at time zone 'America/Chicago')::date;
  l ops.leads%rowtype; touched boolean; n int; nxt text; gap int; what text;
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then raise exception using errcode = '22023', message = 'bad_lead_id'; end if;
  if p_channel not in ('call', 'text', 'facebook', 'email') then raise exception using errcode = '22023', message = 'bad_channel'; end if;
  if p_result not in ('no_answer', 'voicemail', 'talked', 'interested', 'not_interested', 'wrong_number', 'sent') then raise exception using errcode = '22023', message = 'bad_result'; end if;
  if p_channel <> 'call' and p_result <> 'sent' then raise exception using errcode = '22023', message = 'bad_result'; end if;

  select * into l from ops.leads where id = p_lead for update;
  if not found then raise exception using errcode = '22023', message = 'lead_not_found'; end if;
  if l.stage = 'Opted out' then raise exception using errcode = '55000', message = 'lead_opted_out'; end if;
  if l.stage in ('Won', 'Lost') then raise exception using errcode = '22023', message = 'lead_closed'; end if;

  insert into ops.touches (lead_id, channel, result) values (p_lead, p_channel, p_result);
  what := case p_channel when 'call' then 'Called' when 'text' then 'Texted' when 'facebook' then 'Messaged on Facebook' else 'Emailed' end || ' ' || l.business ||
          case p_result when 'no_answer' then ': no answer' when 'voicemail' then ': left a voicemail' when 'talked' then ': talked' when 'interested' then ': interested'
                        when 'not_interested' then ': not interested' when 'wrong_number' then ': wrong number' else '' end;
  insert into ops.activity (agent, action) values ('you', what);

  if p_result = 'not_interested' then
    update ops.leads set stage = 'Lost', next_followup = null, next_channel = '', you_action = '', next_step = 'Not interested (said so on the phone)'
     where id = p_lead;
    perform ops.build_todos();
    return 'lost';
  end if;

  if p_result = 'wrong_number' then
    update ops.leads set phone = '', call_attempts = 0,
      next_channel = ops.plan_channel(touches, '', email, facebook),
      next_followup = today,
      next_step = 'Wrong number. Find a better one (Lead Desk notes or the Detective).',
      my_notes = btrim(my_notes || E'\n' || 'Wrong number: ' || l.phone || ' (' || to_char(today, 'Mon FMDD') || ')')
     where id = p_lead;
    perform ops.build_todos();
    return 'wrong_number';
  end if;

  if p_result = 'no_answer' then
    -- Not a touch. Try again in two days; after two missed calls, send a text today instead.
    update ops.leads set call_attempts = call_attempts + 1,
      next_channel = case when call_attempts + 1 >= 2 then 'text' else 'call' end,
      next_followup = case when call_attempts + 1 >= 2 then today else today + 2 end,
      next_step = case when call_attempts + 1 >= 2 then 'Two missed calls: text them today' else 'No answer, call again ' || to_char(today + 2, 'Dy') end
     where id = p_lead;
    perform ops.build_todos();
    return 'no_answer';
  end if;

  -- A real touch: voicemail, talked, interested, or a text, Facebook message or email sent.
  n := l.touches + 1;
  if p_result = 'voicemail' then
    nxt := 'text'; gap := 0;           -- a quick text right after the voicemail
  else
    nxt := ops.plan_channel(n, l.phone, l.email, l.facebook);
    gap := case n when 1 then 2 when 2 then 3 when 3 then 4 else 5 end;
  end if;

  update ops.leads set
    stage = case when p_result = 'interested' then 'Replied'
                 when stage in ('New', 'Audited', 'Mockup ready') then 'Contacted' else stage end,
    first_contact = coalesce(first_contact, today),
    last_contact = today,
    touches = n,
    call_attempts = 0,
    mockup_requested = case when p_result = 'interested' and coalesce(mockup_url, '') = '' then true else mockup_requested end,
    next_channel = case when p_result = 'interested' then '' else nxt end,
    next_followup = case when p_result = 'interested' or nxt = '' then null else today + gap end,
    you_action = case when p_result = 'interested' then 'Interested on the phone: get their email in Lead Desk; the mockup is queued for the next Tue or Thu run' else '' end,
    next_step = case when p_result = 'interested' then 'Interested. Mockup queued.'
                     when nxt = '' then 'Plan finished. Waiting on them.'
                     else what || ' on ' || to_char(today, 'Mon FMDD') || '. Next: ' ||
                          case nxt when 'call' then 'call' when 'text' then 'text' when 'facebook' then 'Facebook message' else 'email' end ||
                          case when gap = 0 then ' today' else ' ' || to_char(today + gap, 'Dy Mon FMDD') end end
   where id = p_lead;
  perform ops.build_todos();
  return 'ok';
end $$;

-- Next best move now follows the plan's channel.
create or replace function ops.lead_next_move(l ops.leads)
returns text
language sql stable
set search_path to ''
as $$
  select case
    when l.stage in ('Won', 'Lost', 'Opted out') then ''
    when l.stage = 'Replied' then 'Answer them (they replied or are interested)'
    when l.stage = 'Proposal sent' then 'Check in on the proposal'
    when l.stage = 'Contacted' and l.next_followup is not null and l.next_followup <= (now() at time zone 'America/Chicago')::date then
      case l.next_channel when 'call' then 'Call again' when 'text' then 'Text them' when 'facebook' then 'Message them on Facebook'
        else 'Send follow-up ' || (l.touches + 1) || ' (draft in Gmail)' end
    when l.stage = 'Contacted' then 'Wait for the next step on ' || coalesce(to_char(l.next_followup, 'Dy Mon FMDD'), 'the plan')
    when l.next_channel = 'text' and (l.next_followup is null or l.next_followup <= (now() at time zone 'America/Chicago')::date) then 'Text them'
    when l.next_channel = 'call' and l.next_followup > (now() at time zone 'America/Chicago')::date then 'Call again ' || to_char(l.next_followup, 'Dy')
    when l.draft_id <> '' then 'Send the Gmail draft'
    when l.email <> '' and l.email_text <> '' then 'Make the Gmail draft and send it'
    when l.phone <> '' then 'Call them (script on the board)'
    when l.facebook <> '' then 'Message them on Facebook'
    else 'Find a way to reach them' end;
$$;

-- Planner: give the plan room for five touches, and put today's Call Mode queue on the list.
do $do$ declare d text; begin
  d := pg_get_functiondef('ops.build_todos()'::regprocedure);
  d := replace(d, 'where stage = ''Contacted'' and touches >= 4 and last_contact < today - 7;',
                  'where stage = ''Contacted'' and touches >= 5 and last_contact < today - 7;');
  d := replace(d, '  insert into ops.todos (type, item, who, agent, priority)
  select ''Post'',',
'  insert into ops.todos (type, item, who, agent, priority)
  select ''Call'', ''Call Mode: '' || count(*) filter (where ch = ''call'') || '' calls, '' || count(*) filter (where ch = ''text'') || '' texts and '' ||
         count(*) filter (where ch = ''facebook'') || '' Facebook messages due today'', ''Lead Desk'', ''Sales Agent'', 1
    from (select case when stage in (''New'', ''Audited'', ''Mockup ready'') and next_channel = '''' then
                        case when phone <> '''' then ''call'' when facebook <> '''' then ''facebook'' else '''' end
                      else next_channel end as ch
            from ops.leads
           where stage in (''New'', ''Audited'', ''Mockup ready'', ''Contacted'') and heat <> ''Cold''
             and (next_followup is null or next_followup <= today)) q
   where ch in (''call'', ''text'', ''facebook'')
  having count(*) > 0;

  insert into ops.todos (type, item, who, agent, priority)
  select ''Post'',');
  if position('Call Mode:' in d) = 0 or position('touches >= 5' in d) = 0 then raise exception 'build_todos patch failed'; end if;
  execute d;
end $do$;
