-- Phase F.3: rename misspelled report.inquiry_type enum value.
--   archieve_research  →  archive_research
--
-- Coordinated with C# enum member rename
-- (FunderMaps.Core.Types.InquiryType.ArchieveResearch → ArchiveResearch).
-- Npgsql default name translator maps PascalCase ↔ snake_case.
--
-- 9573 records currently use this value (verified 2026-04-25).
--
-- WebFront vector-tile filter has been updated to accept BOTH the old
-- and new strings during the transition window — old tiles still
-- contain 'archieve_research' as a feature property until the worker
-- regenerates them. After the next tile regen completes, a follow-up
-- PR can remove the old string from the WebFront filter.
--
-- Run as: fundermaps (owner)

ALTER TYPE report.inquiry_type RENAME VALUE 'archieve_research' TO 'archive_research';
