-- Every lead gets a ready-to-send email, not just a call script.
-- The Sales Agent writes email_subject and email_text for every reachable lead, even with no address yet.
-- In Lead Desk Thomas can add an address he found (ops.lead_set_email) and turn the email into a Gmail draft;
-- the page creates the draft through his Gmail connector and records it with ops.lead_set_draft.
-- Safe to re-run.

alter table ops.leads add column if not exists email_subject text not null default '';
alter table ops.leads add column if not exists email_text text not null default '';

create or replace function ops.lead_set_email(p_lead text, p_email text)
returns text
language plpgsql
set search_path to ''
as $$
declare l ops.leads%rowtype; e text := lower(btrim(coalesce(p_email, '')));
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'bad_lead_id';
  end if;
  if length(e) > 200 or e !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$' then
    raise exception using errcode = '22023', message = 'bad_email';
  end if;
  select * into l from ops.leads where id = p_lead for update;
  if not found then
    raise exception using errcode = '22023', message = 'lead_not_found';
  end if;
  if l.stage = 'Opted out' then
    raise exception using errcode = '22023', message = 'opted_out';
  end if;
  update ops.leads
     set email = e,
         contact = case when contact ilike '%email%' then contact when contact in ('', 'Not found yet') then 'email' else contact || ', email' end,
         next_step = case when draft_id = '' and touches = 0 then 'Ready for Sales Agent' else next_step end
   where id = p_lead;
  if e <> l.email then
    insert into ops.activity (agent, action) values ('you', 'Added an email for ' || l.business);
  end if;
  return 'saved';
end $$;

create or replace function ops.lead_set_draft(p_lead text, p_draft text)
returns text
language plpgsql
set search_path to ''
as $$
declare l ops.leads%rowtype;
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'bad_lead_id';
  end if;
  if p_draft is null or p_draft !~ '^[A-Za-z0-9_-]{5,100}$' then
    raise exception using errcode = '22023', message = 'bad_draft_id';
  end if;
  select * into l from ops.leads where id = p_lead for update;
  if not found then
    raise exception using errcode = '22023', message = 'lead_not_found';
  end if;
  if l.stage = 'Opted out' then
    raise exception using errcode = '22023', message = 'opted_out';
  end if;
  if l.email = '' then
    raise exception using errcode = '22023', message = 'no_email';
  end if;
  update ops.leads
     set draft_id = p_draft,
         next_step = 'Draft waiting in Gmail',
         you_action = 'Review and send the draft to ' || l.business || ' in Gmail'
   where id = p_lead;
  insert into ops.activity (agent, action) values ('you', 'Made a Gmail draft for ' || l.business);
  return 'saved';
end $$;
