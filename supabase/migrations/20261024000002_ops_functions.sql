-- Helper functions and the two no-AI jobs (Lead Scout, Daily Planner).

create or replace function ops.touch_updated() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists leads_touch on ops.leads;
create trigger leads_touch before update on ops.leads for each row execute function ops.touch_updated();

create or replace function ops.next_lead_id() returns text language sql set search_path = '' as $$
  select 'L' || lpad((coalesce(max(substring(id from 2)::int), 0) + 1)::text, 2, '0') from ops.leads where id ~ '^L[0-9]+$'
$$;

create or replace function ops.heat_for(s int) returns text language sql immutable set search_path = '' as $$
  select case when s >= 78 then 'Hot' when s >= 55 then 'Warm' else 'Cold' end
$$;

create or replace function ops.decode_html(t text) returns text language sql immutable set search_path = '' as $$
  select trim(replace(replace(replace(replace(replace(replace(coalesce(t,''),'&amp;','&'),'&#39;',''''),'&#x27;',''''),'&quot;','"'),'&apos;',''''),'â',''''))
$$;

create or replace function ops.norm_name(t text) returns text language sql immutable set search_path = '' as $$
  select regexp_replace(regexp_replace(lower(coalesce(t,'')), '[^a-z0-9]', '', 'g'), '(llc|inc|co|corp|company|services|service)+$', '')
$$;

-- Lead Scout: reads HomeAdvisor listing pages (JSON-LD), adds new businesses. No AI.
-- Profile pages sit behind a bot check; this never tries to get around it. On 403/429/503 it stops and logs.
create or replace function ops.run_scout(max_pages int default 3) returns text
language plpgsql set search_path = '' as $$
declare
  t record; resp record; j jsonb; it jsonb; nm text; city text; url text;
  added int := 0; pages int := 0; blocked boolean := false; names text[] := '{}'; s int;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
  for t in
    select * from ops.scout_targets where enabled
    order by (niche in ('Pressure washing','Lawn care')) desc, last_run nulls first, near desc, id
    limit max_pages
  loop
    pages := pages + 1;
    select status, content into resp from extensions.http(('GET',
      'https://www.homeadvisor.com/tloc/' || t.city || '-LA/' || t.category,
      array[extensions.http_header('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'),
            extensions.http_header('Accept','text/html')], null, null)::extensions.http_request);
    update ops.scout_targets set last_run = now(), last_status = resp.status,
      enabled = case when resp.status = 404 then false else enabled end where id = t.id;
    if resp.status in (403, 429, 503) then blocked := true; exit; end if;
    if resp.status <> 200 then continue; end if;

    select m[1]::jsonb into j
    from regexp_matches(resp.content, 'ld\+json">(.*?)</script>', 'g') m
    where m[1] like '%SearchResultsPage%' and pg_input_is_valid(m[1], 'jsonb') limit 1;
    if j is null then continue; end if;

    for it in select jsonb_array_elements(coalesce(j->'mainEntity'->'itemListElement', '[]'::jsonb)) loop
      nm := ops.decode_html(it->'item'->>'name');
      city := coalesce(nullif(it->'item'->'address'->>'addressLocality',''), replace(t.city,'-',' '));
      url := it->'item'->>'url';
      if nm = '' or url is null then continue; end if;
      if exists (select 1 from ops.leads where ops.norm_name(business) = ops.norm_name(nm)) then continue; end if;
      if exists (select 1 from ops.clients where ops.norm_name(name) = ops.norm_name(nm)) then continue; end if;
      s := 50 + case when t.niche in ('Pressure washing','Lawn care') then 8 else 0 end
              + case when exists (select 1 from ops.near_cities where city = lower(it->'item'->'address'->>'addressLocality')) then 8 else 0 end;
      insert into ops.leads (id, business, niche, area, found_on, profile_url, score, heat, stage, next_step)
      values (ops.next_lead_id(), nm, t.niche, city, 'HomeAdvisor', 'https://www.homeadvisor.com' || url, s, ops.heat_for(s), 'New',
              'Contact Finder: check Google for a website and phone')
      on conflict do nothing;
      if found then added := added + 1; names := names || nm; end if;
    end loop;
  end loop;

  insert into ops.activity (agent, action) values ('Lead Scout',
    case when blocked then 'HomeAdvisor asked for a bot check, so the scout stopped for today. It will try again next run.'
         else 'Checked ' || pages || ' HomeAdvisor pages and added ' || added || ' new leads' ||
              case when added > 0 then ': ' || array_to_string(names[1:5], ', ') || case when added > 5 then ' and more.' else '.' end else '.' end end);
  update ops.agents set last_run = (now() at time zone 'America/Chicago')::date, status = 'Live',
    last_result = case when blocked then 'Blocked by a bot check today. Will retry next run.' else 'Added ' || added || ' new leads from ' || pages || ' HomeAdvisor pages.' end
  where id = 'scout';
  return 'pages=' || pages || ' added=' || added || ' blocked=' || blocked;
end $$;

-- Daily Planner: rebuilds Thomas's to-do list, closes dead leads, flags stalled agents. No AI.
create or replace function ops.build_todos() returns text
language plpgsql set search_path = '' as $$
declare today date := (now() at time zone 'America/Chicago')::date;
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
  select 'Post', to_char(date, 'Dy Mon FMDD') || ': ' || hook, platforms, 'Content Agent', 3
  from ops.posts where date between today and today + 1;

  insert into ops.todos (type, item, who, agent, priority)
  select 'Fix', name || ' has not run since ' || coalesce(to_char(last_run, 'Mon FMDD'), 'it was set up') || '. Check its scheduled task.', name, 'Daily Planner', 1
  from ops.agents where uses_ai and status = 'Live'
    and coalesce(last_run, today - 30) < today - case when id = 'content' then 8 when id in ('builder','finder') then 4 else 3 end;

  update ops.agents set last_run = today, status = 'Live',
    last_result = (select count(*) from ops.todos) || ' items on your list. ' ||
                  (select count(*) from ops.leads where stage = 'Contacted' and next_followup <= today) || ' follow-ups due for the Sales Agent.'
  where id = 'planner';
  return (select count(*) from ops.todos)::text;
end $$;
