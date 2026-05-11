-- Drop legacy application.user columns left over from the C# WebApi era.
--
-- password_hash       — superseded by Better Auth's account.password.
--                       Nothing in the live stack writes or reads this.
-- access_failed_count — only the dead C# WebApi incremented it. No live
--                       consumer reads it; lockout policy is now BA's job.
-- last_login          — only the dead C# WebApi wrote it. The TS API never
--                       updated it, so the value frontends see has been
--                       stale since the WebApi retired. Dropped rather
--                       than wired up — feature isn't worth the BA hook.
--
-- The still-deployed C# Webservice's only application.user SELECT
-- (UserRepository.GetByAuthKeyAsync) reads
--   id, given_name, last_name, email, job_title, phone_number, role
-- so this drop is safe for it.

ALTER TABLE application.user
    DROP COLUMN password_hash,
    DROP COLUMN access_failed_count,
    DROP COLUMN last_login;
