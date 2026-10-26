-- Google Maps lead source: the Lead Scout also asks Google's Places API (Text Search) for local
-- service businesses. Runs in Postgres, no Claude. Needs Thomas's API key in Supabase Vault under
-- the name 'google_places_api_key' (he adds it himself; it never goes in this repo).
-- Safe to re-run.

create table if not exists ops.maps_targets (
  id serial primary key,
  city text not null,
  niche text not null,
  query text not null unique,
  near boolean not null default false,
  enabled boolean not null default true,
  last_run timestamptz,
  last_status integer,
  last_added integer
);

insert into ops.maps_targets (city, niche, query, near)
select c.city, k.niche, k.term || ' in ' || c.city || ', LA', c.near
from (values ('Gonzales', true), ('Prairieville', true), ('St. Amant', true), ('Geismar', true), ('Sorrento', true),
             ('Donaldsonville', true), ('St. Gabriel', true), ('Baton Rouge', true), ('Denham Springs', false),
             ('Walker', false), ('Zachary', false), ('Central', false), ('Plaquemine', false), ('Port Allen', false),
             ('Hammond', false), ('Livingston', false)) c(city, near)
cross join (values ('pressure washing', 'Pressure washing'), ('lawn care', 'Lawn care'),
                   ('window cleaning', 'Window cleaning'), ('gutter cleaning', 'Gutter cleaning'),
                   ('tree service', 'Tree service'), ('sprinkler repair', 'Irrigation'),
                   ('mobile auto detailing', 'Auto detailing')) k(term, niche)
on conflict (query) do nothing;

create or replace function ops.run_maps_scout(max_queries integer default 2)
returns text
language plpgsql
set search_path to ''
as $function$
declare
  api_key text;
  t record;
  resp record;
  j jsonb;
  p jsonb;
  nm text;
  addr text;
  parts text[];
  lead_city text;
  site text;
  reviews int;
  stars numeric;
  s int;
  added int := 0;
  queries int := 0;
  blocked boolean := false;
  key_problem int;
  names text[] := array[]::text[];
  t_added int;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'google_places_api_key' limit 1;
  if api_key is null or api_key = '' then
    update ops.agents
      set last_result = split_part(coalesce(last_result, ''), ' Google Maps:', 1) || ' Google Maps: waiting for an API key.'
      where id = 'scout';
    return 'no_key';
  end if;

  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '25');
  for t in
    select * from ops.maps_targets where enabled
    order by (niche in ('Pressure washing', 'Lawn care')) desc, last_run nulls first, near desc, id
    limit max_queries
  loop
    queries := queries + 1;
    t_added := 0;
    select status, content into resp from extensions.http((
      'POST',
      'https://places.googleapis.com/v1/places:searchText',
      array[
        extensions.http_header('X-Goog-Api-Key', api_key),
        extensions.http_header('X-Goog-FieldMask',
          'places.displayName,places.formattedAddress,places.nationalPhoneNumber,places.websiteUri,places.rating,places.userRatingCount,places.googleMapsUri,places.businessStatus')
      ],
      'application/json',
      jsonb_build_object('textQuery', t.query, 'pageSize', 20, 'regionCode', 'US')::text
    )::extensions.http_request);

    update ops.maps_targets set last_run = now(), last_status = resp.status where id = t.id;
    if resp.status in (429, 503) then
      blocked := true;
      exit;
    end if;
    if resp.status in (400, 401, 403) then
      key_problem := resp.status;
      exit;
    end if;
    if resp.status <> 200 or not pg_input_is_valid(resp.content, 'jsonb') then
      continue;
    end if;
    j := resp.content::jsonb;

    for p in select jsonb_array_elements(coalesce(j->'places', '[]'::jsonb))
    loop
      nm := btrim(coalesce(p->'displayName'->>'text', ''));
      addr := coalesce(p->>'formattedAddress', '');
      if nm = '' or coalesce(p->>'businessStatus', 'OPERATIONAL') <> 'OPERATIONAL' then
        continue;
      end if;
      -- Louisiana only, and keep just the town: never store a street address.
      if addr !~ ', LA( [0-9]{5})?(,|$)' then
        continue;
      end if;
      parts := string_to_array(addr, ', ');
      lead_city := case when array_length(parts, 1) >= 3 then parts[array_length(parts, 1) - 2] else t.city end;
      if lead_city ~ '[0-9]' then
        lead_city := t.city;
      end if;
      if exists (select 1 from ops.leads where ops.norm_name(business) = ops.norm_name(nm))
         or exists (select 1 from ops.clients where ops.norm_name(name) = ops.norm_name(nm)) then
        continue;
      end if;

      site := nullif(btrim(coalesce(p->>'websiteUri', '')), '');
      reviews := coalesce((p->>'userRatingCount')::int, 0);
      stars := (p->>'rating')::numeric;
      s := 50
        + case when site is null then 20 else 0 end
        + case when reviews >= 25 then 15 when reviews >= 10 then 10 else 0 end
        + case when stars >= 4.8 and reviews >= 5 then 5 else 0 end
        + case when exists (select 1 from ops.near_cities nc where nc.city = lower(lead_city)) then 8 else 0 end
        + case when t.niche in ('Pressure washing', 'Lawn care') then 8 else 0 end;
      s := least(s, 100);

      insert into ops.leads (id, business, niche, area, found_on, profile_url, rating, website, phone, contact,
                             score, heat, stage, next_step)
      values (
        ops.next_lead_id(), nm, t.niche, lead_city, 'Google Maps',
        coalesce(p->>'googleMapsUri', ''),
        case when stars is not null then stars::text || ' (' || reviews || ' reviews)' else '' end,
        case when site is null then 'None found (no website on Google Maps)'
             else 'Not checked (' || regexp_replace(site, '^https?://(www\.)?([^/]+).*$', '\2') || ')' end,
        coalesce(p->>'nationalPhoneNumber', ''),
        coalesce(p->>'nationalPhoneNumber', ''),
        s, ops.heat_for(s), 'New',
        case when site is null then 'Contact Finder: look for an email and a Facebook page'
             else 'Contact Finder: rate their website and look for an email' end
      ) on conflict do nothing;
      if found then
        added := added + 1;
        t_added := t_added + 1;
        names := names || nm;
      end if;
    end loop;
    update ops.maps_targets set last_added = t_added where id = t.id;
  end loop;

  insert into ops.activity (agent, action) values (
    'Lead Scout',
    case
      when key_problem is not null then
        'Google Maps refused the API key (error ' || key_problem || '). Check the key and that Places API (New) is turned on in Google Cloud.'
      when blocked then 'Google Maps said to slow down, so the scout stopped for today.'
      else 'Searched Google Maps ' || queries || ' times and added ' || added || ' new leads'
        || case when added > 0 then ': ' || array_to_string(names[1:5], ', ') || case when added > 5 then ' and more.' else '.' end
           else '.' end
    end
  );
  update ops.agents
    set last_run = (now() at time zone 'America/Chicago')::date,
        status = 'Live',
        last_result = split_part(coalesce(last_result, ''), ' Google Maps:', 1) || ' Google Maps: ' ||
          case when key_problem is not null then 'the API key was refused.'
               when blocked then 'paused for today.'
               else 'added ' || added || ' new leads.' end
    where id = 'scout';
  return 'queries=' || queries || ' added=' || added || ' blocked=' || blocked || ' key_problem=' || coalesce(key_problem::text, 'none');
end $function$;

update ops.agents set
  role = 'Pulls new local service businesses from HomeAdvisor and Google Maps on its own and adds them to the pipeline. Runs inside the database, no Claude.'
where id = 'scout';

-- 6:35 AM CDT, right after the HomeAdvisor pass.
select cron.unschedule(jobname) from cron.job where jobname = 'ops-maps-scout';
select cron.schedule('ops-maps-scout', '35 11 * * 1-5', $$select ops.run_maps_scout(2)$$);

-- The Facebook scout (a Claude step in the Mon/Wed/Fri Sales Agent run) rotates through the same towns and niches.
alter table ops.maps_targets add column if not exists fb_last_run timestamptz;
