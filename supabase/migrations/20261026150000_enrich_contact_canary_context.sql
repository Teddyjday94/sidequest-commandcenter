-- Give isolated Contact Finder jobs enough trusted lead context to distinguish
-- same-name businesses without exposing private addresses or unrelated fields.

create or replace function ops.enrich_contact_verification_input()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  lead_context record;
begin
  if new.kind <> 'contact_verification' or new.lead_id is null then
    return new;
  end if;

  select l.business, l.niche, l.area, l.found_on, l.profile_url, l.website, l.heat, l.score
  into lead_context
  from ops.leads l
  where l.id = new.lead_id;

  if found then
    new.input := coalesce(new.input, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'business', left(lead_context.business, 200),
      'niche', left(lead_context.niche, 200),
      'area', left(lead_context.area, 200),
      'found_on', left(lead_context.found_on, 200),
      'profile_url', left(lead_context.profile_url, 2000),
      'website_state', left(lead_context.website, 500),
      'heat', left(lead_context.heat, 50),
      'score', lead_context.score
    ));
  end if;

  return new;
end
$$;

drop trigger if exists ops_jobs_enrich_contact_context on ops.jobs;
create trigger ops_jobs_enrich_contact_context
before insert or update of lead_id, kind, input on ops.jobs
for each row execute function ops.enrich_contact_verification_input();

revoke all on function ops.enrich_contact_verification_input() from public, anon, authenticated;
