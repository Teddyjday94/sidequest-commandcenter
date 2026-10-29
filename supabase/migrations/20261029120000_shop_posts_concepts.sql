-- Elsewhere Supply Co.: concept art links on ideas, and the social post plan the Idea Board shows
-- under "Posts". Thomas posts everything himself and marks it Posted (ops.shop_post_mark).
-- Safe to re-run.
alter table ops.shop_ideas add column if not exists concept_url text not null default '';

create table if not exists ops.shop_posts (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  day date not null,
  platform text not null,          -- TikTok, Instagram Reel, Instagram carousel, Instagram story, Pinterest
  product text not null default '',
  format text not null default '',
  hook text not null default '',
  script text not null default '', -- shots and on-screen text, in order
  caption text not null default '',
  hashtags text not null default '',
  status text not null default 'planned' check (status in ('planned', 'posted', 'skipped')),
  posted_at timestamptz
);
alter table ops.shop_posts enable row level security;
create index if not exists shop_posts_day_idx on ops.shop_posts (day, id);

create or replace function ops.shop_post_mark(p_id bigint, p_status text)
returns text
language plpgsql
set search_path to ''
as $$
declare r ops.shop_posts%rowtype;
begin
  if p_status not in ('planned', 'posted', 'skipped') then raise exception using errcode = '22023', message = 'bad_status'; end if;
  select * into r from ops.shop_posts where id = p_id for update;
  if not found then raise exception using errcode = '22023', message = 'post_not_found'; end if;
  update ops.shop_posts set status = p_status, posted_at = case when p_status = 'posted' then now() else null end where id = p_id;
  if p_status = 'posted' then
    insert into ops.activity (agent, action) values ('you', 'Posted the ' || r.product || ' ' || r.platform || ' post');
  end if;
  return p_status;
end $$;
