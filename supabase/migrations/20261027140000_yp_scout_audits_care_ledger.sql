-- Three new crew members and a second free lead source, all mechanical work in Postgres (no Claude):
-- 1. ops.run_yp_scout: Yellow Pages search pages, rotating through ops.maps_targets. Keeps only businesses with
--    no website or only a Yellow Pages template site. Stops on a bot check, like the HomeAdvisor scout.
-- 2. Site Auditor: ops.run_site_audits loads each lead's own website and records plain-English problems
--    (slow, not set up for phones, no tap-to-call, no form, no https, old copyright, template builder)
--    in ops.site_audits. The Detective and Sales Agent pitch with these.
-- 3. Client Care: ops.check_client_sites checks every launched client site daily. The Claude part
--    (check-ins, review requests, care-plan offers) is in the playbook, section 10.
-- 4. Bookkeeper: ops.ledger keeps one row per Stripe invoice; the Claude part (reading Stripe, drafting
--    reminders) is in the playbook, section 11.
-- Safe to re-run.

alter table ops.maps_targets add column if not exists yp_last_run timestamptz;

create or replace function ops.run_yp_scout(max_pages int default 4)
returns text
language plpgsql
set search_path to ''
as $$
declare
  t record; resp record; blk text; nm text; href text; site text; phone text; loc text; town text; cats text; nic text;
  added int := 0; pages int := 0; blocked boolean := false; names text[] := '{}'; s int; web text; hook text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
  for t in
    select * from ops.maps_targets where enabled
    order by (niche in ('Pressure washing', 'Lawn care')) desc, yp_last_run nulls first, near desc, id
    limit max_pages
  loop
    pages := pages + 1;
    begin
      select status, content into resp from extensions.http(('GET',
        'https://www.yellowpages.com/search?search_terms=' || replace(lower(t.niche), ' ', '+') || '&geo_location_terms=' || replace(t.city, ' ', '+') || '%2C+LA',
        array[extensions.http_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'),
              extensions.http_header('Accept', 'text/html')], null, null)::extensions.http_request);
    exception when others then
      update ops.maps_targets set yp_last_run = now() where id = t.id;
      continue;
    end;
    update ops.maps_targets set yp_last_run = now() where id = t.id;
    if resp.status in (403, 429, 503) then blocked := true; exit; end if;
    if resp.status <> 200 then continue; end if;

    foreach blk in array string_to_array(resp.content, '<div class="result"') loop
      nm := ops.decode_html((regexp_match(blk, 'class="business-name"[^>]*><span>([^<]+)</span>'))[1]);
      if nm is null or nm = '' then continue; end if;
      href := (regexp_match(blk, 'class="business-name" href="([^"]+)"'))[1];
      site := (regexp_match(blk, 'class="track-visit-website" href="([^"]+)"'))[1];
      phone := btrim((regexp_match(blk, 'class="phones[^"]*">([^<]+)<'))[1]);
      loc := (regexp_match(blk, 'class="locality">([^<]+)<'))[1];
      town := initcap(btrim(split_part(coalesce(loc, ''), ',', 1)));
      -- Yellow Pages mixes related trades into a search, so the niche comes from the listing's own categories.
      cats := lower(coalesce((regexp_match(blk, 'class="categories">(.*?)</div>'))[1], ''));
      nic := case when cats ~ 'non-profit|nonprofit|social service|church|school|government|association' then 'skip'
                  when cats ~ 'pressure|power wash|softwash|soft wash' then 'Pressure washing'
                  when cats ~ 'lawn|landscap|grass|mowing|yard|tree service|sod' then 'Lawn care'
                  when cats ~ 'window clean' then 'Window cleaning'
                  when cats ~ 'paint' then 'Painting'
                  when cats ~ 'clean|janitor|maid' then 'Cleaning'
                  when cats ~ 'handyman|home improvement|remodel' then 'Handyman'
                  when cats = '' then t.niche
                  else 'Other services' end;
      if nic = 'skip' then continue; end if;
      -- Only nearby businesses, and only ones without a real website of their own.
      if town = '' or not exists (select 1 from ops.near_cities c where c.city = lower(town)) then continue; end if;
      if site is not null and site !~* 'localsearch\.com' then continue; end if;
      if exists (select 1 from ops.leads where ops.norm_name(business) = ops.norm_name(nm)) then continue; end if;
      if exists (select 1 from ops.clients where ops.norm_name(name) = ops.norm_name(nm)) then continue; end if;
      if site is null then
        web := 'None found (Yellow Pages listing only)';
        hook := 'Listed on Yellow Pages but has no website of its own.';
      else
        web := 'Weak site (' || (regexp_match(site, '//([^/]+)'))[1] || ', Yellow Pages template)';
        hook := 'Their only site is a Yellow Pages template page.';
      end if;
      s := least(100, 50 + case when site is null then 20 else 12 end
                         + case when nic in ('Pressure washing', 'Lawn care') then 8 else 0 end + 8);
      insert into ops.leads (id, business, niche, area, found_on, profile_url, website, phone, contact, score, heat, stage, hook, next_step)
      values (ops.next_lead_id(), nm, nic, town, 'Yellow Pages', case when href is null then '' else 'https://www.yellowpages.com' || href end,
              web, coalesce(phone, ''), coalesce(phone, 'Yellow Pages page'), s, ops.heat_for(s), 'Audited', hook,
              case when coalesce(phone, '') <> '' then 'Call them (script on board)' else 'Find a way to reach them' end)
      on conflict do nothing;
      if found then added := added + 1; names := names || nm; end if;
    end loop;
  end loop;

  insert into ops.activity (agent, action) values ('Lead Scout',
    case when blocked then 'Yellow Pages asked for a bot check, so that scout stopped for today. It will try again next run.'
         else 'Checked ' || pages || ' Yellow Pages searches and added ' || added || ' leads with no real website' ||
              case when added > 0 then ': ' || array_to_string(names[1:5], ', ') || case when added > 5 then ' and more.' else '.' end else '.' end end);
  return 'pages=' || pages || ' added=' || added || ' blocked=' || blocked;
end $$;

-- Site Auditor ---------------------------------------------------------------------------------------
create table if not exists ops.site_audits (
  lead_id text primary key references ops.leads (id) on delete cascade,
  url text not null,
  checked_at timestamptz not null default now(),
  http_status int,
  load_ms int,
  page_kb int,
  https boolean,
  mobile_ready boolean,
  tap_to_call boolean,
  has_form boolean,
  has_description boolean,
  copyright_year int,
  builder text not null default '',
  issues text not null default '',
  score int
);
alter table ops.site_audits enable row level security;

-- The lead's own site, pulled from the website text the scouts and Contact Finder write.
create or replace function ops.lead_site_url(p_website text)
returns text
language sql immutable
set search_path to ''
as $$
  select case when p_website is null or p_website ~* '^\s*none' then null else
    'http://' || (regexp_match(lower(p_website), '((?:[a-z0-9-]+\.)+(?:com|net|org|biz|us|co|info|site|online|pro|services|llc|io|business|website))\M'))[1] end;
$$;

create or replace function ops.audit_site(p_lead text)
returns text
language plpgsql
set search_path to ''
as $$
declare
  l ops.leads%rowtype; u text; resp record; t0 timestamptz; ms int; c text; yr int; cy int := extract(year from now())::int;
  iss text[] := '{}'; sc int := 100; b text := ''; secure boolean;
begin
  select * into l from ops.leads where id = p_lead;
  u := ops.lead_site_url(l.website);
  if u is null then return 'no site'; end if;
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');
  t0 := clock_timestamp();
  begin
    select status, content, headers into resp from extensions.http(('GET', u,
      array[extensions.http_header('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1')],
      null, null)::extensions.http_request);
  exception when others then
    insert into ops.site_audits (lead_id, url, checked_at, http_status, issues, score)
    values (p_lead, u, now(), 0, 'The site did not load when we checked it (confirm before mentioning it).', 10)
    on conflict (lead_id) do update set url = excluded.url, checked_at = now(), http_status = 0, load_ms = null, issues = excluded.issues, score = 10;
    return 'failed';
  end;
  ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  c := lower(coalesce(resp.content, ''));
  secure := exists (select 1 from unnest(resp.headers) h where h.field ilike 'location' and h.value ilike 'https://%');
  if resp.status <> 200 then
    iss := iss || ('The site returned an error (' || resp.status || ') when we loaded it.'); sc := sc - 40;
  end if;
  if ms > 3000 then iss := iss || ('Took ' || round(ms / 1000.0, 1) || ' seconds just to start loading.'); sc := sc - 15; end if;
  if c !~ '<meta[^>]+name=["'']?viewport' then iss := iss || 'Not set up for phones, so it shows up tiny and zoomed out.'::text; sc := sc - 20; end if;
  if c !~ 'href=["'']tel:' then iss := iss || 'No tap-to-call phone link for mobile visitors.'::text; sc := sc - 10; end if;
  if c !~ '<form' then iss := iss || 'No contact or quote request form.'::text; sc := sc - 10; end if;
  if not secure then iss := iss || 'Does not switch visitors to a secure https address.'::text; sc := sc - 10; end if;
  if c !~ 'name=["'']?description' then iss := iss || 'No description for Google to show in search results.'::text; sc := sc - 5; end if;
  select max(m[1]::int) into yr from regexp_matches(c, '(?:©|&copy;|copyright)[^0-9]{0,24}((?:19|20)[0-9]{2})', 'g') m;
  if yr is not null and yr < cy - 1 then iss := iss || ('Footer copyright still says ' || yr || '.'); sc := sc - 5; end if;
  b := case when u ~ 'localsearch\.com' then 'Yellow Pages template'
            when c ~ 'wixstatic|wix\.com' then 'Wix'
            when c ~ 'wsimg\.com|godaddy' then 'GoDaddy builder'
            when c ~ 'squarespace' then 'Squarespace'
            when c ~ 'weebly' then 'Weebly'
            when c ~ 'sites\.google' then 'Google Sites'
            when c ~ 'wp-content' then 'WordPress'
            else '' end;
  if b in ('Yellow Pages template', 'GoDaddy builder', 'Weebly', 'Google Sites') then iss := iss || ('Built on a ' || b || ' that looks like every other one.'); sc := sc - 5; end if;
  insert into ops.site_audits (lead_id, url, checked_at, http_status, load_ms, page_kb, https, mobile_ready, tap_to_call, has_form, has_description, copyright_year, builder, issues, score)
  values (p_lead, u, now(), resp.status, ms, length(c) / 1024, secure, c ~ '<meta[^>]+name=["'']?viewport', c ~ 'href=["'']tel:', c ~ '<form',
          c ~ 'name=["'']?description', yr, b, array_to_string(iss, E'\n'), greatest(0, sc))
  on conflict (lead_id) do update set url = excluded.url, checked_at = now(), http_status = excluded.http_status, load_ms = excluded.load_ms,
    page_kb = excluded.page_kb, https = excluded.https, mobile_ready = excluded.mobile_ready, tap_to_call = excluded.tap_to_call,
    has_form = excluded.has_form, has_description = excluded.has_description, copyright_year = excluded.copyright_year,
    builder = excluded.builder, issues = excluded.issues, score = excluded.score;
  return 'score=' || greatest(0, sc);
end $$;

create or replace function ops.run_site_audits(max_sites int default 10)
returns text
language plpgsql
set search_path to ''
as $$
declare r record; n int := 0; weak int := 0; res text;
begin
  for r in
    select l.id from ops.leads l left join ops.site_audits a on a.lead_id = l.id
     where l.stage not in ('Won', 'Lost', 'Opted out') and ops.lead_site_url(l.website) is not null
       and (a.lead_id is null or a.checked_at < now() - interval '30 days')
     order by a.checked_at nulls first, l.score desc
     limit max_sites
  loop
    res := ops.audit_site(r.id); n := n + 1;
    if exists (select 1 from ops.site_audits where lead_id = r.id and score < 70) then weak := weak + 1; end if;
  end loop;
  if n > 0 then
    insert into ops.activity (agent, action) values ('Site Auditor', 'Checked ' || n || ' lead websites; ' || weak || ' have real problems to pitch on.');
  end if;
  update ops.agents set last_run = (now() at time zone 'America/Chicago')::date, status = 'Live',
    last_result = 'Checked ' || n || ' websites, ' || weak || ' weak. ' || (select count(*) from ops.site_audits) || ' audits on file.'
   where id = 'auditor';
  return 'checked=' || n || ' weak=' || weak;
end $$;

-- Client Care ----------------------------------------------------------------------------------------
alter table ops.builds add column if not exists launched_at date;
alter table ops.builds add column if not exists site_ok boolean;
alter table ops.builds add column if not exists site_checked_at timestamptz;
alter table ops.builds add column if not exists checkin_draft_id text not null default '';
alter table ops.builds add column if not exists review_draft_id text not null default '';
alter table ops.builds add column if not exists care_notes text not null default '';

create or replace function ops.check_client_sites()
returns text
language plpgsql
set search_path to ''
as $$
declare b record; resp record; n int := 0; down int := 0;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');
  for b in select id, live_domain from ops.builds where status = 'Launched' and coalesce(live_domain, '') <> '' loop
    n := n + 1;
    begin
      select status into resp from extensions.http(('GET', 'https://' || regexp_replace(b.live_domain, '^https?://', ''),
        array[extensions.http_header('User-Agent', 'Mozilla/5.0 (Sidequest site check)')], null, null)::extensions.http_request);
      update ops.builds set site_ok = (resp.status = 200), site_checked_at = now() where id = b.id;
      if resp.status <> 200 then down := down + 1; end if;
    exception when others then
      update ops.builds set site_ok = false, site_checked_at = now() where id = b.id; down := down + 1;
    end;
  end loop;
  if down > 0 then
    insert into ops.activity (agent, action) values ('Client Care', down || ' client site' || case when down = 1 then ' did' else 's did' end || ' not load this morning. Check Vercel.');
  end if;
  return 'checked=' || n || ' down=' || down;
end $$;

-- Bookkeeper -----------------------------------------------------------------------------------------
create table if not exists ops.ledger (
  invoice_id text primary key,
  lead_id text references ops.leads (id),
  business text not null default '',
  kind text not null default 'deposit',          -- deposit or balance
  amount numeric not null default 0,
  status text not null default 'draft',          -- Stripe status: draft, open, paid, void, uncollectible
  due_date date,
  paid_at date,
  reminder_draft_id text not null default '',
  updated_at timestamptz not null default now()
);
alter table ops.ledger enable row level security;

-- Crew rows ------------------------------------------------------------------------------------------
insert into ops.agents (id, ord, name, role, status, schedule, next_run, uses_ai)
values ('auditor', 11, 'Site Auditor', 'Loads each lead''s own website and records what is wrong with it in plain words (slow, not set up for phones, no tap-to-call, no form, no https, old copyright, template builder), so the pitch names real problems. Runs inside the database, no Claude.', 'Live', 'Weekdays about 6:45 AM (free)', 'next weekday 6:45 AM', false),
       ('care', 12, 'Client Care', 'Checks every launched client site daily, then on Sundays drafts the 2-week review request, the 30-day check-in and care-plan offers for Thomas to send.', 'Live', 'Sites daily (free); drafts Sundays 5:43 PM', 'Sun 5:43 PM', true),
       ('bookkeeper', 13, 'Bookkeeper', 'Reads Stripe on Friday mornings, keeps the ledger of deposits and balances, drafts the balance invoice at launch and polite payment reminders, and adds the money line to the Friday brief.', 'Live', 'Fridays 9:17 AM (with the Sales Agent)', 'Fri 9:17 AM', true)
on conflict (id) do update set name = excluded.name, role = excluded.role, schedule = excluded.schedule, uses_ai = excluded.uses_ai;

update ops.agents set role = role || ' Also searches Yellow Pages every weekday morning (free) for nearby businesses with no website or only a Yellow Pages template.'
 where id = 'scout' and role not ilike '%Yellow Pages every weekday%';

-- Daily Planner: also watch the new agents, and flag client sites that are down. --------------------
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
  select 'Build', you_action, business, case when status = 'Launched' then 'Client Care' else 'Site Builder' end, 1
  from ops.builds where you_action <> '';

  insert into ops.todos (type, item, who, agent, priority)
  select 'Fix', business || '''s site did not load when we checked it. Look at the Vercel project.', business, 'Client Care', 1
  from ops.builds where status = 'Launched' and site_ok = false;

  insert into ops.todos (type, item, who, agent, priority)
  select 'Post', to_char(date, 'Dy Mon FMDD') || ': ' || hook, platforms, 'Content Agent', 3
  from ops.posts where date between today and today + 1;

  insert into ops.todos (type, item, who, agent, priority)
  select 'Fix', name || ' has not run since ' || coalesce(to_char(last_run, 'Mon FMDD'), 'it was set up') || '. Check its scheduled task.', name, 'Daily Planner', 1
  from ops.agents where uses_ai and status = 'Live' and id in ('finder','detective','sales','builder','site','content','replies','strategist','care','bookkeeper')
    and last_run is not null
    and last_run < today - case when id in ('content','strategist','care','bookkeeper') then 8 when id in ('builder','site','detective') then 5 when id = 'finder' then 4 else 3 end;

  get diagnostics n = row_count;
  update ops.agents set last_run = today, status = 'Live',
    last_result = (select count(*) from ops.todos) || ' items on your list. ' ||
                  (select count(*) from ops.leads where stage = 'Contacted' and next_followup <= today) || ' follow-ups due for the Sales Agent.'
  where id = 'planner';
  return (select count(*) from ops.todos)::text;
end $function$;

-- Schedules (UTC): Yellow Pages after HomeAdvisor, audits before the planner, client sites daily.
select cron.unschedule(jobid) from cron.job where jobname in ('ops-yp-scout', 'ops-site-auditor', 'ops-client-sites');
select cron.schedule('ops-yp-scout', '40 11 * * 1-5', $$select ops.run_yp_scout(4)$$);
select cron.schedule('ops-site-auditor', '44 11 * * 1-5', $$select ops.run_site_audits(10)$$);
select cron.schedule('ops-client-sites', '20 12 * * *', $$select ops.check_client_sites()$$);

-- Settings Thomas fills in for Client Care. Blank until he does.
insert into ops.settings (key, value) values ('google_review_link', ''), ('care_plan_offer', '') on conflict (key) do nothing;
