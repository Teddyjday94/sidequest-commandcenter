-- Monday morning brief: one function that counts last week for both businesses, so the Monday Sales run
-- only has to add Shopify sales and write the brief (playbook 4c). "Last week" is the 7 days before today
-- in America/Chicago. Read only. Safe to re-run.
create or replace function ops.weekly_brief()
returns jsonb
language sql stable
set search_path to ''
as $$
  with d as (select (now() at time zone 'America/Chicago')::date as today),
  w as (select today - 7 as since, today from d)
  select jsonb_build_object(
    'week', (select to_char(since, 'Mon FMDD') || ' to ' || to_char(today - 1, 'Mon FMDD') from w),
    'sidequest', jsonb_build_object(
      'calls', (select count(*) from ops.touches t, w where t.channel = 'call' and t.at >= w.since and t.at < w.today),
      'calls_answered', (select count(*) from ops.touches t, w where t.channel = 'call' and t.result in ('talked', 'interested', 'not_interested') and t.at >= w.since and t.at < w.today),
      'texts_sent', (select count(*) from ops.touches t, w where t.channel = 'text' and t.at >= w.since and t.at < w.today),
      'emails_and_messages', (select count(*) from ops.touches t, w where t.channel in ('email', 'facebook') and t.at >= w.since and t.at < w.today),
      'interested', (select count(*) from ops.touches t, w where t.result = 'interested' and t.at >= w.since and t.at < w.today),
      'replied', (select count(*) from ops.lead_events e, w where e.stage = 'Replied' and e.at >= w.since and e.at < w.today),
      'won', (select count(*) from ops.lead_events e, w where e.stage = 'Won' and e.at >= w.since and e.at < w.today),
      'new_leads', (select count(*) from ops.leads l, w where l.created_at >= w.since and l.created_at < w.today),
      'mockups_built', (select count(*) from ops.activity a, w where a.agent in ('builder', 'Mockup Builder') and a.action ilike '%mockup%' and a.at >= w.since and a.at < w.today),
      'open_leads', (select count(*) from ops.leads where stage not in ('Won', 'Lost', 'Opted out')),
      'hot_leads', (select count(*) from ops.leads where stage not in ('Won', 'Lost', 'Opted out') and heat = 'Hot'),
      'calls_due_today', (select count(*) from ops.leads l, d where l.stage not in ('Won', 'Lost', 'Opted out') and l.phone <> '' and l.heat <> 'Cold'
                            and (l.next_followup is null or l.next_followup <= d.today)
                            and (l.next_channel = 'call' or (l.next_channel = '' and l.stage in ('New', 'Audited', 'Mockup ready')))),
      'paid_this_week', (select coalesce(sum(amount), 0) from ops.ledger g, w where g.status = 'paid' and g.paid_at >= w.since and g.paid_at < w.today),
      'money_owed', (select coalesce(sum(amount), 0) from ops.ledger where status in ('open', 'draft')),
      'sites_building', (select count(*) from ops.builds where status not in ('Launched')),
      'top_moves', (select coalesce(jsonb_agg(m), '[]') from (
          select l.business, l.phone, ops.lead_next_move(l) as move
            from ops.leads l where l.stage not in ('Won', 'Lost', 'Opted out')
           order by ops.lead_priority(l) desc limit 5) m)
    ),
    'elsewhere', jsonb_build_object(
      'ideas_new', (select count(*) from ops.shop_ideas where status = 'new'),
      'ideas_liked_or_made', (select count(*) from ops.shop_ideas s, w where s.status in ('liked', 'made') and s.marked_at >= w.since),
      'designs_ready', (select count(*) from ops.shop_ideas where design_url <> '' and status <> 'made'),
      'designs_waiting', (select count(*) from ops.shop_ideas where design_requested),
      'products_launched', (select count(*) from ops.shop_launches s, w where s.launched_at >= w.since and s.launched_at < w.today),
      'posts_planned', (select count(*) from ops.shop_posts p, w where p.day >= w.since and p.day < w.today),
      'posts_posted', (select count(*) from ops.shop_posts p, w where p.day >= w.since and p.day < w.today and p.status = 'posted'),
      'posts_this_week', (select count(*) from ops.shop_posts p, d where p.day >= d.today and p.day < d.today + 7),
      'articles_published', (select count(*) from ops.shop_articles a, w where a.published_at >= w.since and a.published_at < w.today),
      'top_idea', (select slogan from ops.shop_ideas where status = 'new' order by score desc, created_at desc limit 1)
    )
  );
$$;
