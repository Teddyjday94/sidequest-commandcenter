-- Print-ready designs for Trend Scout ideas. design_slug names the files published with the Idea Board
-- (designs/<slug>-dark-ink.png for light garments, designs/<slug>-light-ink.png for dark garments,
-- 300 DPI, transparent); print_note says where and how big to place it in Printify.
-- Safe to re-run.
alter table ops.shop_ideas add column if not exists design_slug text not null default '';
alter table ops.shop_ideas add column if not exists print_note text not null default '';

update ops.shop_ideas set design_slug = v.slug, print_note = v.note from (values
 ('Arrived Late / Leaving Early / Great Time', 'arrived-late', 'Front center, 11.3 in wide, about 3 in below the collar. Dark ink file on Sand and Light Pink; light ink file on Black, Forest Green and Maroon.'),
 ('Fell Back. / Never Got Up.', 'fell-back', 'Front center, 12 in wide, about 3.5 in below the collar. Light ink file on Black, Dark Heather, Navy and Forest Green.'),
 ('Will Return Your Text / in Q1', 'return-text', 'Left chest, scale to 4 in wide. Dark ink file on Sand and Light Pink; light ink file on Black and Military Green.'),
 ('Micro-Retired / Back Never', 'micro-retired', 'Front center, 11 to 12 in wide, about 3 in below the collar. Dark ink file on Natural, Butter and Ivory; light ink file on Blue Jean and Pepper.'),
 ('Coffee Badging / Since 9:04 AM', 'coffee-badging', 'Front center, 9 in wide, about 3.5 in below the collar. Dark ink file on White, Natural and Athletic Heather; light ink file on Black.')
) as v(slogan, slug, note) where ops.shop_ideas.slogan = v.slogan and ops.shop_ideas.design_slug = '';
