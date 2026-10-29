-- Elsewhere Supply Co. (Thomas's Shopify store, Printify print on demand): the Trend + Design Scout.
-- The weekly scout writes design briefs into ops.shop_ideas. Thomas marks each one in the Idea Board
-- (liked, passed, made) through ops.shop_idea_mark; the scout reads those marks and the store's sales
-- to learn what to look for next week. Nothing here touches the store itself.
-- Safe to re-run.

create table if not exists ops.shop_ideas (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  week date not null default (date_trunc('week', now() at time zone 'America/Chicago'))::date,
  slogan text not null,                       -- the words printed on the shirt, exactly
  concept text not null default '',           -- the joke in one or two plain sentences
  theme text not null default '',             -- introvert, meme, ai, literary, seasonal, travel, work, other
  why_now text not null default '',           -- the trend and the evidence it is moving
  sources text[] not null default '{}',       -- links the scout used as evidence
  risk text not null default '',              -- trademark / copycat check result in plain words
  garment text not null default '',           -- tee, hoodie, crewneck, beanie, hat, mug, sticker
  colors text not null default '',            -- garment colors that suit the design
  design_brief text not null default '',      -- layout, type style, size, placement, ink colors
  listing_title text not null default '',
  listing_description text not null default '',
  tags text[] not null default '{}',
  price numeric(8,2),
  score int not null default 50,              -- 0 to 100: fit with the brand x trend strength x low risk
  status text not null default 'new' check (status in ('new', 'liked', 'passed', 'made')),
  thomas_note text not null default '',
  product_handle text not null default '',    -- set when Thomas made it and it is in the store
  marked_at timestamptz
);
alter table ops.shop_ideas enable row level security;
create unique index if not exists shop_ideas_slogan_idx on ops.shop_ideas (lower(slogan));
create index if not exists shop_ideas_status_idx on ops.shop_ideas (status, score desc);

-- Thomas's buttons on the Idea Board.
create or replace function ops.shop_idea_mark(p_id bigint, p_status text, p_note text default null, p_handle text default null)
returns text
language plpgsql
set search_path to ''
as $$
declare r ops.shop_ideas%rowtype;
begin
  if p_status not in ('new', 'liked', 'passed', 'made') then raise exception using errcode = '22023', message = 'bad_status'; end if;
  select * into r from ops.shop_ideas where id = p_id for update;
  if not found then raise exception using errcode = '22023', message = 'idea_not_found'; end if;
  update ops.shop_ideas set status = p_status,
    thomas_note = coalesce(left(p_note, 1000), thomas_note),
    product_handle = coalesce(left(p_handle, 200), product_handle),
    marked_at = now()
   where id = p_id;
  insert into ops.activity (agent, action) values ('you',
    case p_status when 'liked' then 'Liked' when 'passed' then 'Passed on' when 'made' then 'Made' else 'Reset' end || ' shirt idea "' || r.slogan || '"');
  return p_status;
end $$;

insert into ops.agents (id, ord, name, role, status, schedule, next_run, hands_to, uses_ai)
values ('trends', 40, 'Trend Scout', 'Finds trending jokes for Elsewhere Supply Co. and writes shirt design briefs', 'Live', 'Sundays, after Client Care', 'next Sunday evening', 'Thomas (Idea Board)', true)
on conflict (id) do nothing;

insert into ops.settings (key, value) values
('shop_brand', 'Elsewhere Supply Co. sells dry, low-key funny apparel for people who would rather be somewhere else: introverts, the chronically online, the tired, the overbooked. Jokes are deadpan and specific, never mean, never political, no profanity. Current lines: out of office / introvert (Currently Elsewhere Hoodie, Do Not Perceive Me Beanie), meme (Ships in 6 to 7 Business Days Tee), AI satire (Not AI. Just Tired. Tee), literary travel (Odysseus Layover Tee), seasonal (Seasonal Depression World Tour Hoodie). Tees $28 to $32, hoodies $52 to $54, beanies $26. Printify fulfills everything.'),
('shop_lessons', '')
on conflict (key) do nothing;
