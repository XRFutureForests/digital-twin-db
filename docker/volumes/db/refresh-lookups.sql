-- Reload every lookup table from data/lookups/*.csv at the end of a fresh init,
-- after all migrations: the CSVs are the source of truth for reference data,
-- the snapshot's copy of them only the state on the day it was cut.
SELECT * FROM shared.refresh_all_lookups();
