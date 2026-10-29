-- Elsewhere Supply Co.: Product Launcher (playbook 12c), Weekly Social Planner (12d) and Blog Writer (12e).
-- ops.shop_launches: one row per Shopify product the Launcher has finished (so it only works on new ones).
-- ops.shop_articles: blog posts the Blog Writer published, so it never repeats a topic.
-- Safe to re-run.
create table if not exists ops.shop_launches (
  product_id text primary key,       -- gid://shopify/Product/...
  handle text not null default '',
  title text not null default '',
  launched_at timestamptz not null default now(),
  notes text not null default ''     -- what the Launcher changed, and anything Thomas should check
);
alter table ops.shop_launches enable row level security;

create table if not exists ops.shop_articles (
  id bigint generated always as identity primary key,
  article_id text not null default '',
  handle text not null default '',
  title text not null,
  topic text not null default '',
  keywords text not null default '',
  products text[] not null default '{}',
  published_at timestamptz not null default now()
);
alter table ops.shop_articles enable row level security;

insert into ops.shop_launches (product_id, handle, title, notes) values
 ('gid://shopify/Product/8831409029281', 'currently-elsewhere-hoodie', 'Currently Elsewhere Hoodie', 'Existing product, cleaned up by hand on Oct 29'),
 ('gid://shopify/Product/8831409160353', 'ships-in-6-7-business-days-tee', 'Ships in 6-7 Business Days Tee', 'Existing product, cleaned up by hand on Oct 29'),
 ('gid://shopify/Product/8831409258657', 'not-ai-just-tired-tee', 'Not AI. Just Tired. Tee', 'Existing product, cleaned up by hand on Oct 29'),
 ('gid://shopify/Product/8831409389729', 'odysseus-layover-tee', 'Odysseus Layover Tee', 'Existing product, cleaned up by hand on Oct 29'),
 ('gid://shopify/Product/8831409422497', 'seasonal-depression-world-tour-hoodie', 'Seasonal Depression World Tour Hoodie', 'Existing product, cleaned up by hand on Oct 29'),
 ('gid://shopify/Product/8831409488033', 'do-not-perceive-me-beanie', 'Do Not Perceive Me Beanie', 'Existing product, cleaned up by hand on Oct 29')
on conflict (product_id) do nothing;

insert into ops.agents (id, ord, name, role, status, schedule, next_run, hands_to, uses_ai) values
 ('launcher', 41, 'Product Launcher', 'Finishes new Elsewhere Supply Co. listings: copy, SEO, tags, alt text, collections', 'Live', 'Weekday mornings, in the Sales Agent run', 'next weekday 9:17 AM', 'Thomas (store)', true),
 ('socialplan', 42, 'Social Planner', 'Plans next week''s Elsewhere Supply Co. TikTok, Instagram and Pinterest posts', 'Live', 'Sundays, after the Trend Scout', 'next Sunday evening', 'Thomas (Idea Board, Posts)', true),
 ('blogger', 43, 'Blog Writer', 'Writes one gift guide or SEO blog post a week for Elsewhere Supply Co.', 'Live', 'Sundays, after the Social Planner', 'next Sunday evening', 'Store blog', true)
on conflict (id) do nothing;
