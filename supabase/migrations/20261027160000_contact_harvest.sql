-- Contact sweep: find emails and phones a business published on its own website, for free, every weekday.
-- ops.harvest_contacts loads each open lead's site (home page plus up to two contact pages) and keeps:
--   * a mailto: address, or
--   * a plain-text address whose name or domain clearly belongs to the business,
-- skipping junk (font credits, platform addresses, image file names). Never guesses an address.
-- contact_source records the page the email came from. The Detective's web search covers leads
-- whose sites have no email (playbook section 8, Contact hunt).
-- Safe to re-run.

alter table ops.leads add column if not exists contact_source text not null default '';
alter table ops.leads add column if not exists contacts_checked_at timestamptz;

create or replace function ops.pick_business_email(p_text text, p_business text, p_site text)
returns text
language plpgsql stable
set search_path to ''
as $$
declare e text; root text; tok text; junk text := '(example|sentry|wixpress|wix\.com|godaddy|yourdomain|domain\.com|email\.com|\.png|\.jpg|\.gif|\.webp|\.svg|typedesign|fontawesome|fonts\.|schema\.org|w3\.org|localsearch|yellowpages|squarespace|wordpress|noreply|no-reply|@sentry|cloudflare|googleapis)';
begin
  root := split_part(regexp_replace(lower(coalesce(p_site, '')), '^https?://(www\.)?', ''), '.', 1);
  -- 1. a mailto link the business put on its page
  for e in select lower(m[1]) from regexp_matches(coalesce(p_text, ''), 'mailto:([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})', 'g') m loop
    if e !~ junk then return e; end if;
  end loop;
  -- 2. a plain address that clearly belongs to this business (its domain, or a word from its name)
  for e in select lower(m[1]) from regexp_matches(coalesce(p_text, ''), '([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:com|net|org|us|biz|info|co))\M', 'g') m loop
    if e ~ junk then continue; end if;
    if length(root) >= 5 and position(left(root, 6) in e) > 0 then return e; end if;
    foreach tok in array regexp_split_to_array(lower(coalesce(p_business, '')), '[^a-z0-9]+') loop
      if length(tok) >= 5 and tok not in ('services', 'service', 'lawns', 'company', 'pressure', 'washing', 'cleaning', 'landscaping', 'landscape', 'maintenance', 'solutions', 'enterprises') and position(tok in e) > 0 then return e; end if;
    end loop;
  end loop;
  return null;
end $$;

create or replace function ops.harvest_contacts(max_leads int default 15)
returns text
language plpgsql
set search_path to ''
as $$
declare
  r record; resp record; base text; page text; body text; link text; links text[]; e text; tel text; src text;
  n int := 0; got_e int := 0; got_p int := 0; names text[] := '{}';
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');
  for r in
    select l.id, l.business, l.email, l.phone, l.contact, l.touches, l.draft_id, ops.lead_site_url(l.website) as u
      from ops.leads l
     where l.stage not in ('Won', 'Lost', 'Opted out')
       and (l.email = '' or l.phone = '')
       and ops.lead_site_url(l.website) is not null
       and (l.contacts_checked_at is null or l.contacts_checked_at < now() - interval '14 days')
     order by ops.lead_priority(l) desc
     limit max_leads
  loop
    n := n + 1; body := ''; src := ''; links := '{}';
    base := r.u;
    begin
      select status, content into resp from extensions.http(('GET', base,
        array[extensions.http_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36')], null, null)::extensions.http_request);
      if resp.status = 200 then body := coalesce(resp.content, ''); src := base; end if;
    exception when others then null;
    end;
    -- up to two contact or about pages linked from the home page
    for link in select distinct m[1] from regexp_matches(body, 'href="([^"#]*(?:contact|about)[^"#]*)"', 'gi') m limit 2 loop
      page := case when link ~* '^https?://' then link when left(link, 1) = '/' then base || link else base || '/' || link end;
      if page !~* ('^https?://(www\.)?' || regexp_replace(base, '^https?://', '')) then continue; end if;
      begin
        select status, content into resp from extensions.http(('GET', page,
          array[extensions.http_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36')], null, null)::extensions.http_request);
        if resp.status = 200 then body := body || ' ' || coalesce(resp.content, ''); links := links || page; end if;
      exception when others then null;
      end;
    end loop;

    e := case when r.email = '' then ops.pick_business_email(body, r.business, base) end;
    tel := case when r.phone = '' then (regexp_match(body, 'href="tel:([+0-9().\s-]{10,20})"', 'i'))[1] end;
    tel := nullif(regexp_replace(coalesce(tel, ''), '[^0-9]', '', 'g'), '');
    if tel is not null and length(tel) = 11 and left(tel, 1) = '1' then tel := substr(tel, 2); end if;
    if tel is not null and length(tel) <> 10 then tel := null; end if;

    update ops.leads set
      email = coalesce(e, email),
      phone = coalesce('(' || substr(tel, 1, 3) || ') ' || substr(tel, 4, 3) || '-' || substr(tel, 7), phone),
      contact = case when e is not null and contact not ilike '%email%' then case when contact in ('', 'Not found yet') then 'email' else contact || ', email' end else contact end,
      contact_source = case when e is not null then 'Their own website: ' || coalesce(links[1], src) else contact_source end,
      next_step = case when e is not null and touches = 0 and draft_id = '' then 'Ready for Sales Agent' else next_step end,
      contacts_checked_at = now()
    where id = r.id;
    if e is not null then got_e := got_e + 1; names := names || r.business; end if;
    if tel is not null then got_p := got_p + 1; end if;
  end loop;
  if got_e + got_p > 0 then
    insert into ops.activity (agent, action) values ('Detective', 'Contact sweep checked ' || n || ' lead websites: ' || got_e || ' new email' || case when got_e = 1 then '' else 's' end ||
      case when got_e > 0 then ' (' || array_to_string(names[1:4], ', ') || case when got_e > 4 then ' and more' else '' end || ')' else '' end || ', ' || got_p || ' new phone' || case when got_p = 1 then '.' else 's.' end);
  end if;
  return 'checked=' || n || ' emails=' || got_e || ' phones=' || got_p;
end $$;

select cron.unschedule(jobid) from cron.job where jobname = 'ops-contact-sweep';
select cron.schedule('ops-contact-sweep', '47 11 * * 1-5', $$select ops.harvest_contacts(15)$$);
