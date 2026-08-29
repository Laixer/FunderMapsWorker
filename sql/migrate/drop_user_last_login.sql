-- Drop application.user.last_login — written only by the retired C# stack.
--
-- FunderMaps.Data/Repositories/UserRepository.cs set it on every C# sign-in;
-- nothing in FunderMapsApi (Better Auth tracks sessions instead), the Bun
-- Webservice, Worker, Windmill or the frontends reads or writes it. Frozen
-- since 2026-04-29 (last C# WebApi login); 0 rows touched since August.
-- No view, function or index depends on the column.
--
-- Run as: fundermaps (owner of application."user").

ALTER TABLE application."user" DROP COLUMN last_login;
