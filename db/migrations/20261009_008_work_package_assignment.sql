-- Work packages per colleague, composed by the admin: dataops.work_package_assignment.
--
-- The Studio's Vandaag page shows "werkpakketten": named filters on the review
-- queue (WORK_PACKAGES in the Studio's src/services/workPackages.ts). Until now
-- every reviewer ticked their own packages, stored in that browser only
-- (localStorage 'vandaag.packages'): another computer started empty, and the
-- admin could not say who works on what. The admin asked (2026-10-09) to
-- compose the packages per colleague so they show up in that colleague's
-- Vandaag on any computer.
--
-- The package ids are defined by the Studio, not here: the database only
-- stores which ids a user was given. The CHECK keeps them slug-shaped so a
-- typo or an injection attempt cannot land in the table; an id the Studio no
-- longer knows is simply not shown.
--
-- The API's PUT /api/management/work-packages/:userId replaces a user's set
-- (delete + insert in one transaction), GET /api/dataops/work-packages/me reads
-- your own. No UPDATE grant: a row is either there or not.
--
-- On prod 2026-10-09: no such table; application.user.id is uuid;
-- fundermaps_api is a member of fundermaps_webapp. A new, empty table: no
-- rewrite, no lock on anything existing beyond the FK check on application.user.

CREATE TABLE dataops.work_package_assignment (
    user_id     uuid        NOT NULL REFERENCES application."user"(id) ON DELETE CASCADE,
    package_id  text        NOT NULL CHECK (package_id ~ '^[a-z0-9-]{1,64}$'),
    assigned_by uuid        REFERENCES application."user"(id) ON DELETE SET NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, package_id)
);

COMMENT ON TABLE dataops.work_package_assignment IS
'Work packages (Studio Vandaag filters) the admin assigned to a colleague. One row per user and package; the set is replaced as a whole by PUT /api/management/work-packages/:userId. No rows = the user picks their own packages in the browser.';
COMMENT ON COLUMN dataops.work_package_assignment.user_id IS
'The colleague who works this package. Rows go with the user.';
COMMENT ON COLUMN dataops.work_package_assignment.package_id IS
'Work package id as defined by the Studio (WORK_PACKAGES in src/services/workPackages.ts), e.g. meldingen-funderingstype. The database does not know the list; unknown ids are ignored by the Studio.';
COMMENT ON COLUMN dataops.work_package_assignment.assigned_by IS
'The admin who composed this set; NULL once that account is gone.';
COMMENT ON COLUMN dataops.work_package_assignment.assigned_at IS
'When the set containing this row was saved.';

ALTER TABLE dataops.work_package_assignment OWNER TO fundermaps;

GRANT SELECT, INSERT, DELETE ON dataops.work_package_assignment TO fundermaps_webapp;
