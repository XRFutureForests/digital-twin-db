-- =============================================================================
-- entity_matches.method register: first_campaign
-- =============================================================================
-- XRFF-465 / XRFF-478. The first campaign at a site creates every entity it
-- observes, also where later campaigns follow (ECOSENSE: inventory, then TLS).
-- single_campaign stays for sites with one campaign only. The column is
-- deliberately unconstrained; its comment is the register.
--
-- Mirrored to init 86-entity-match-method-first-campaign.sql.
-- =============================================================================

COMMENT ON COLUMN trees.entity_matches.method IS
    'How the decision was reached. Deliberately unconstrained so a new method needs no migration; values in use: first_campaign (the first campaign at its site: every observation it makes is new), single_campaign (the only campaign at its site), tag_number (field tag or tree number), spatial (position gate plus attribute check, e.g. mutual nearest partner within 1 m and a compatible DBH), manual (a person''s review).';
