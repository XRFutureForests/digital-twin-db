-- The silva menu entry quotes a runtime that is half the real one.
--
-- The description is what someone reads to answer "should I press this?", so
-- the number in it is load-bearing. It said "about 30 s for ecosense (1,495
-- trees), 10 s for mathisle", written before either had been timed on the
-- server that now runs them.
--
-- Measured on dt.unr, 20-year runs through the job queue: ecosense 63 s
-- (jobs 21), mathisle 21 s (job 18), and 8 s for a 5-year mathisle run (job
-- 22). Direct container runs agree -- ecosense completed in ~67 s three times.
-- So ecosense was understated by roughly a factor of two.
--
-- Also states that the horizon is what moves the number, because `years` is the
-- one parameter a person is likely to change without expecting a cost, and adds
-- the two facts a first-time caller needs and cannot see: a dry run is free and
-- writes nothing, and both sites already carry a silva_2030..2045 chain, so a
-- promoting run refuses unless it is told to replace it.
--
-- Targets whichever row holds workflow_key = 'silva', for the same reason as
-- 20260910120000: the key moves to a new row on a silvaR version bump, and
-- process_ids differ between deployments.

UPDATE shared.Processes
SET description =
    'Project a variant forward with the SILVA growth model and write the '
    'result back as a chain of simulated_growth variants, one per 5-year '
    'period. A 20-year run takes about 60 s for ecosense (1,495 trees) and '
    '20 s for mathisle (730); cost grows with the horizon and, steeply, with '
    'the number of trees. dry_run=true simulates and writes nothing, which is '
    'the way to see what a run would do before doing it. Appends to '
    'trees.GrowthSimulations, which accumulates -- running it twice gives two '
    'comparable runs, not a corrupted one. Both sites already carry a '
    'silva_2030..2045 variant chain, so a promoting run refuses the duplicate '
    'names: use no_promote=true to record a trajectory for comparison without '
    'touching the chain Unreal reads, or replace=true only when you do mean to '
    'overwrite it.'
WHERE workflow_key = 'silva';
