-- Reference data and schedules. Safe to re-run.
create extension if not exists pg_cron;

insert into ops.scout_targets (city, category, niche, near)
select c.city, k.category, k.niche, c.near
from (values ('Gonzales',true),('Prairieville',true),('Saint-Amant',true),('Geismar',true),('Sorrento',true),('Donaldsonville',true),('Saint-Gabriel',true),('Baton-Rouge',true),
             ('Denham-Springs',false),('Walker',false),('Zachary',false),('Central',false),('Plaquemine',false),('Port-Allen',false),('Hammond',false),('Livingston',false)) c(city, near)
cross join (values ('Exterior-Surfaces-Powerwashing','Pressure washing'),('Driveway-or-Concrete-Power-Washing','Pressure washing'),('Roof-Clean','Pressure washing'),
                   ('Lawn-Care-Fall-Clean-Up','Lawn care'),('Lawn-Care-Maintain-and-Mow-A-Lawn','Lawn care'),
                   ('Window-Cleaning','Window cleaning'),('Gutters-Downspouts-Clean','Gutter cleaning'),('Trees-and-Shrubs-Trim-or-Remove','Tree service'),
                   ('Lawn-and-Garden-Sprinkler-System-Install','Irrigation')) k(category, niche)
on conflict do nothing;

insert into ops.near_cities values ('gonzales'),('prairieville'),('st. amant'),('saint amant'),('geismar'),('sorrento'),('donaldsonville'),
  ('st. gabriel'),('saint gabriel'),('baton rouge'),('darrow'),('dutchtown'),('port vincent'),('french settlement') on conflict do nothing;

insert into ops.clients values ('Ascension Wash N'' Geaux'),('Ascension Mow N'' Geaux'),('Helping Hands Lawn Care'),('Vargo Automotive'),
  ('Aim to Please Salon and Gifts'),('Chocolate Oracle'),('Catera''s Creation'),('Loop and Petal'),('Don''s Seafood'),('Rhino Window Tint'),
  ('Legacy Tattoo Studio'),('Boba Lover') on conflict do nothing;

insert into ops.settings values ('mailing_address','Sidequest Creative, 12060 Alex Road, Gonzales, LA 70737'),
  ('dashboard_url','https://claude.ai/artifact/LjDPvPRUYEfi4DPcsrtYmN') on conflict (key) do nothing;

-- Times are UTC. 11:30 UTC = 6:30 AM CDT / 5:30 AM CST.
select cron.unschedule(jobname) from cron.job where jobname in ('ops-lead-scout','ops-daily-planner','ops-afternoon-planner');
select cron.schedule('ops-lead-scout', '30 11 * * 1-5', $$select ops.run_scout(3)$$);
select cron.schedule('ops-daily-planner', '50 11 * * 1-5', $$select ops.build_todos()$$);
select cron.schedule('ops-afternoon-planner', '15 21 * * 1-5', $$select ops.build_todos()$$);
