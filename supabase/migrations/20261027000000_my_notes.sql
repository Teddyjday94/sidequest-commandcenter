-- Thomas's own notes on a lead (owner name, photo links, anything he saw on Facebook or Google).
-- Written from Lead Desk through ops.lead_note(); the Detective, Sales Agent and builders treat it as trusted.
-- Safe to re-run.

alter table ops.leads add column if not exists my_notes text not null default '';

create or replace function ops.lead_note(p_lead text, p_note text)
returns text
language plpgsql
set search_path to ''
as $$
declare l ops.leads%rowtype;
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then
    raise exception using errcode = '22023', message = 'bad_lead_id';
  end if;
  if p_note is null or length(p_note) > 4000 then
    raise exception using errcode = '22023', message = 'note_too_long';
  end if;
  select * into l from ops.leads where id = p_lead for update;
  if not found then
    raise exception using errcode = '22023', message = 'lead_not_found';
  end if;
  update ops.leads set my_notes = btrim(p_note) where id = p_lead;
  if btrim(p_note) <> btrim(l.my_notes) then
    insert into ops.activity (agent, action) values ('you', 'Updated your notes on ' || l.business);
  end if;
  return 'saved';
end $$;
