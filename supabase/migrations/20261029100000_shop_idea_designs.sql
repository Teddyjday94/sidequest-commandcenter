-- Illustrated designs for Trend Scout ideas, made by the Shop Designer (playbook 12b) with an Artlist
-- image model and turned into 300 DPI transparent PNGs. Files live in the Idea Board artifact's asset
-- store; design_url points at the print file, design_preview_url at a small preview on a shirt color.
-- Thomas asks for a design with the Idea Board's "Design it" button (ops.shop_idea_design).
-- Safe to re-run.
alter table ops.shop_ideas add column if not exists design_requested boolean not null default false;
alter table ops.shop_ideas add column if not exists design_url text not null default '';
alter table ops.shop_ideas add column if not exists design_preview_url text not null default '';
alter table ops.shop_ideas add column if not exists design_prompt text not null default '';
alter table ops.shop_ideas add column if not exists design_model text not null default '';
alter table ops.shop_ideas add column if not exists print_note text not null default '';
alter table ops.shop_ideas add column if not exists design_feedback text not null default '';

create or replace function ops.shop_idea_design(p_id bigint, p_feedback text default null)
returns text
language plpgsql
set search_path to ''
as $$
declare r ops.shop_ideas%rowtype;
begin
  select * into r from ops.shop_ideas where id = p_id for update;
  if not found then raise exception using errcode = '22023', message = 'idea_not_found'; end if;
  update ops.shop_ideas set design_requested = true,
    design_feedback = coalesce(left(nullif(btrim(p_feedback), ''), 1000), design_feedback),
    status = case when status = 'new' then 'liked' else status end,
    marked_at = now()
   where id = p_id;
  insert into ops.activity (agent, action) values ('you', case when r.design_url = '' then 'Asked for a design: "' else 'Asked for a new version of the design: "' end || r.slogan || '"');
  return 'requested';
end $$;
