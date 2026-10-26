-- Photos Thomas uploads in Lead Desk for a lead's mockup. The files live in the Lead Desk artifact's
-- asset store; this table records which asset belongs to which lead. The Mockup Builder downloads them
-- and ships them with the mockup. Safe to re-run.

create table if not exists ops.lead_photos (
  asset_id text primary key check (asset_id ~ '^[A-Za-z0-9_-]{16,64}$'),
  lead_id text not null references ops.leads(id) on delete cascade,
  file_name text not null default '',
  caption text not null default '',
  content_type text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists lead_photos_lead on ops.lead_photos (lead_id, created_at);

create or replace function ops.add_lead_photo(p_lead text, p_asset text, p_name text, p_type text)
returns text language plpgsql set search_path to '' as $$
begin
  if p_lead is null or p_lead !~ '^L[0-9]{1,5}$' then raise exception using errcode = '22023', message = 'bad_lead_id'; end if;
  if p_asset is null or p_asset !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception using errcode = '22023', message = 'bad_asset_id'; end if;
  if not exists (select 1 from ops.leads where id = p_lead) then raise exception using errcode = '22023', message = 'lead_not_found'; end if;
  insert into ops.lead_photos (asset_id, lead_id, file_name, content_type)
  values (p_asset, p_lead, left(coalesce(p_name, ''), 200), left(coalesce(p_type, ''), 60))
  on conflict (asset_id) do nothing;
  return 'saved';
end $$;

create or replace function ops.caption_lead_photo(p_asset text, p_caption text)
returns text language plpgsql set search_path to '' as $$
begin
  if p_asset is null or p_asset !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception using errcode = '22023', message = 'bad_asset_id'; end if;
  update ops.lead_photos set caption = left(coalesce(p_caption, ''), 200) where asset_id = p_asset;
  return 'saved';
end $$;

create or replace function ops.remove_lead_photo(p_asset text)
returns text language plpgsql set search_path to '' as $$
begin
  if p_asset is null or p_asset !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception using errcode = '22023', message = 'bad_asset_id'; end if;
  delete from ops.lead_photos where asset_id = p_asset;
  return 'removed';
end $$;
