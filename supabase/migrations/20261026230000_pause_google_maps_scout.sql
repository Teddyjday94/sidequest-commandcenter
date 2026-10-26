-- Thomas chose not to set up Google billing, so the Google Maps scout is off. ops.run_maps_scout()
-- and ops.maps_targets stay: the targets now drive the Directory Scout's town and niche rotation
-- (fb_last_run), and the Maps scout can be turned back on with a Vault key and this cron job.
select cron.unschedule(jobname) from cron.job where jobname = 'ops-maps-scout';
update ops.agents set
  role = 'Pulls new local service businesses from HomeAdvisor on its own every weekday morning. Runs inside the database, no Claude. Facebook, Yelp, Nextdoor and other directories are searched by the Directory Scout on Mon, Wed and Fri.',
  last_result = split_part(coalesce(last_result, ''), ' Google Maps:', 1)
where id = 'scout';
