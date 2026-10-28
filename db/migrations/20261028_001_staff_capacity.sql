-- Capacity per colleague for the review-queue dispatcher (FunderMapsApi #277; Yorick 2026-10-28: "Can be done now").
--
-- Work in the review queue is to be pushed to people instead of everyone filtering one shared queue. The dispatcher
-- (FunderMapsApi POST /api/dataops/dispatch, run by a Windmill schedule) needs to know who takes work and how much:
-- hours per week, the weekdays they work, and optionally the document kinds they prefer (report.inquiry_type codes
-- as the reader reads them; everyone can do everything, a preference only weighs the choice). One row per colleague;
-- no row, or active = false, means the dispatcher gives that person nothing. How many hours someone works is staff
-- data: it lives here and never in the public repos.
--
-- On prod (2026-10-28): no such table. The assignment plumbing exists and is unused (dossier.assigned_to/assigned_at,
-- API POST /api/dataops/dossier/:id/assign; 0 of ~1,050 open dossiers assigned on 2026-10-22). The admin edits rows
-- through the API (/api/management/capacity), so fundermaps_webapp gets SELECT, INSERT, UPDATE, DELETE.

SET LOCAL lock_timeout = '2s';

CREATE TABLE dataops.staff_capacity (
    user_id uuid PRIMARY KEY REFERENCES application."user"(id) ON DELETE CASCADE,
    hours_per_week numeric(4,1) NOT NULL CHECK (hours_per_week >= 0 AND hours_per_week <= 60),
    working_days smallint[] NOT NULL DEFAULT '{1,2,3,4,5}'
        CHECK (cardinality(working_days) BETWEEN 1 AND 7 AND working_days <@ '{1,2,3,4,5,6,7}'::smallint[]),
    preferred_kinds text[] NOT NULL DEFAULT '{}' CHECK (cardinality(preferred_kinds) <= 20),
    active boolean NOT NULL DEFAULT true,
    updated_by uuid REFERENCES application."user"(id) ON DELETE SET NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE dataops.staff_capacity IS 'How much review-queue work a colleague takes, for the dispatcher (FunderMapsApi #277). No row or active = false: the dispatcher assigns this person nothing.';
COMMENT ON COLUMN dataops.staff_capacity.user_id IS 'The colleague (a member of the platform organisation). The row goes with the user.';
COMMENT ON COLUMN dataops.staff_capacity.hours_per_week IS 'Hours a week spent on the review queue; the dispatcher derives how many open dossiers the person holds from it.';
COMMENT ON COLUMN dataops.staff_capacity.working_days IS 'ISO weekdays the person works: 1 = Monday … 7 = Sunday. The dispatcher assigns new work on these days only.';
COMMENT ON COLUMN dataops.staff_capacity.preferred_kinds IS 'Document kinds (report.inquiry_type codes as the reader reads them) this person prefers; empty = no preference. A preference weighs the choice, it never excludes anyone.';
COMMENT ON COLUMN dataops.staff_capacity.active IS 'false = keep the numbers but assign nothing (holiday, absence).';
COMMENT ON COLUMN dataops.staff_capacity.updated_by IS 'The admin who last saved the row; NULL once that account is gone.';

ALTER TABLE dataops.staff_capacity OWNER TO fundermaps;
GRANT SELECT, INSERT, UPDATE, DELETE ON dataops.staff_capacity TO fundermaps_webapp;
