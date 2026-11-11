-- XR Future Forests Lab — the lab team and its datasets
--
-- OPTIONAL — applied manually, after the campaigns exist (ecosense_mathisle_campaigns.sql,
-- import_pathfinder.py):
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -1 < scripts/seed/xrfflab_team.sql
--
-- What this does (XRFF-670)
-- =========================
-- Write access is scoped per campaign: a contributor may write into campaigns their team
-- owns, and into campaigns with no owner team. With no team at all, every contributor
-- account could write into every dataset. This creates the team XRFFLab and makes it the
-- owner of every campaign that has no owner yet (owner, 2026-11-11: the lab owns all
-- datasets during the test phase).
--
-- After it, only XRFFLab members and curators write into these datasets. Curators and
-- admins are not affected (their role reaches every campaign); add lab contributors to the
-- team on the portal's account page or with public.add_team_member().
--
-- Idempotent: the team is created once; a re-run gives the team only campaigns that still
-- have no owner, so a campaign a curator moved to another team stays there.

INSERT INTO shared.teams (team_name, description, created_by)
VALUES ('XRFFLab',
        'XR Future Forests Lab, University of Freiburg. Owns the lab''s datasets during the test phase (XRFF-670).',
        'seed: xrfflab_team.sql')
ON CONFLICT (team_name) DO NOTHING;

UPDATE shared.campaigns
   SET owner_team_id = (SELECT team_id FROM shared.teams WHERE team_name = 'XRFFLab')
 WHERE owner_team_id IS NULL;
