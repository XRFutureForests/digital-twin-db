-- =============================================================================
-- Only curators may change a campaign's owner team (XRFF-670)
-- =============================================================================
-- Writes are scoped per campaign: a contributor may write into campaigns their
-- team owns and into campaigns with no owner team. The UPDATE policy on
-- shared.campaigns checks the row before and after on its own, so it let a
-- contributor claim an unowned campaign for their team, or set their team's
-- campaign back to no owner, which opens it to every contributor.
--
-- RLS cannot compare OLD with NEW, so a BEFORE UPDATE trigger does. It refuses
-- the change for API callers (JWT role anon or authenticated) who are not
-- curators. Direct connections (seed scripts, silva-connector: no JWT) and the
-- service role are not API accounts and pass. public.campaigns_update() writes
-- the base table, so the view path is covered as well.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.guard_campaign_owner_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.owner_team_id IS DISTINCT FROM OLD.owner_team_id
       AND coalesce(auth.jwt() ->> 'role', '') IN ('anon', 'authenticated')
       AND NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators may change the owner team of a campaign'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator to move the campaign to another team.';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION shared.guard_campaign_owner_change() IS
    'BEFORE UPDATE trigger on shared.campaigns: refuses a change of owner_team_id by an API account that is not a curator (XRFF-670).';

REVOKE ALL ON FUNCTION shared.guard_campaign_owner_change() FROM PUBLIC;

DROP TRIGGER IF EXISTS trigger_campaigns_owner_change ON shared.campaigns;
CREATE TRIGGER trigger_campaigns_owner_change
    BEFORE UPDATE OF owner_team_id ON shared.campaigns
    FOR EACH ROW EXECUTE FUNCTION shared.guard_campaign_owner_change();
