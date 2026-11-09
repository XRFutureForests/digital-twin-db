-- Give four insertable public views the column defaults of their base tables.
--
-- public.environments, public.point_clouds, public.sensors and public.stems are
-- written through INSTEAD OF INSERT triggers that copy the whole row with
-- `INSERT INTO <base> SELECT NEW.*`. A view column has no default unless one is
-- set on the view itself, so a column the caller leaves out arrives in NEW as an
-- explicit NULL, and the base table's default never fires. Inserting a point
-- cloud, environment, sensor or stem without its id therefore failed with a
-- NOT NULL violation on the id; created_at, is_active and the other defaulted
-- columns were written as NULL.
--
-- The other insert triggers name their columns and are not affected.
--
-- View defaults are lost when a view is dropped and recreated: a migration that
-- recreates one of these four views must set them again.

ALTER VIEW public.environments ALTER COLUMN environment_id SET DEFAULT nextval('environments.environments_environment_id_seq'::regclass);
ALTER VIEW public.environments ALTER COLUMN created_at     SET DEFAULT now();

ALTER VIEW public.point_clouds ALTER COLUMN point_cloud_id SET DEFAULT nextval('point_clouds.point_clouds_point_cloud_id_seq'::regclass);
ALTER VIEW public.point_clouds ALTER COLUMN created_at     SET DEFAULT now();

ALTER VIEW public.sensors ALTER COLUMN sensor_id         SET DEFAULT nextval('sensor.sensors_sensor_id_seq'::regclass);
ALTER VIEW public.sensors ALTER COLUMN created_at        SET DEFAULT now();
ALTER VIEW public.sensors ALTER COLUMN installation_date SET DEFAULT now();
ALTER VIEW public.sensors ALTER COLUMN is_active         SET DEFAULT true;
ALTER VIEW public.sensors ALTER COLUMN external_metadata SET DEFAULT '{}'::jsonb;

ALTER VIEW public.stems ALTER COLUMN stem_id    SET DEFAULT nextval('trees.stems_stem_id_seq'::regclass);
ALTER VIEW public.stems ALTER COLUMN created_at SET DEFAULT now();
