-- One-off backfill (2026-09-04): give the existing dossiers the timeline the
-- new writers produce from now on, synthesized from the facts already stored.
-- Idempotent: every INSERT is guarded on "no entry of this kind/link yet".
BEGIN;

-- received: every dossier arrived once
INSERT INTO dataops.dossier_entry (dossier_id, at, kind, actor_kind, actor, text, visible_to_melder)
SELECT d.id, d.received_at, 'received', CASE WHEN d.channel='upload' THEN 'melder' ELSE 'system' END::dataops.actor_kind,
       d.channel::text,
       CASE WHEN d.reference IS NOT NULL THEN 'Melding '||d.reference||' ontvangen' ELSE 'Document ontvangen ('||d.channel||')' END,
       true
FROM dataops.dossier d
WHERE NOT EXISTS (SELECT 1 FROM dataops.dossier_entry e WHERE e.dossier_id=d.id AND e.kind='received');

-- extraction: the latest reading per artifact (earlier superseded readings add noise, not history worth showing)
INSERT INTO dataops.dossier_entry (dossier_id, at, kind, actor_kind, actor, text, body, artifact_id, extraction_id, visible_to_melder)
SELECT a.dossier_id, ex.finished_at, 'extraction', 'pipeline', ex.model,
       'Document gelezen ('||ex.lane||'): '||(SELECT count(*) FROM dataops.extraction_field f WHERE f.extraction_id=ex.id AND f.state<>'rejected')||' voorstel(len)',
       jsonb_build_object('lane', ex.lane, 'backfilled', true),
       a.id, ex.id, true
FROM dataops.extraction ex
JOIN dataops.artifact a ON a.id=ex.artifact_id
WHERE ex.id=(SELECT max(id) FROM dataops.extraction WHERE artifact_id=a.id) AND ex.finished_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dataops.dossier_entry e WHERE e.extraction_id=ex.id AND e.kind='extraction');

-- verdict: one entry per decision
INSERT INTO dataops.dossier_entry (dossier_id, at, kind, actor_kind, actor, text, verdict_id, visible_to_melder)
SELECT a.dossier_id, v.decided_at, 'verdict', 'reviewer', v.decided_by::text,
       CASE v.outcome WHEN 'confirmed' THEN 'Waarde overgenomen: ' WHEN 'corrected' THEN 'Waarde aangepast: ' ELSE 'Waarde afgekeurd: ' END
         ||f.field||' = '||coalesce(v.final_value, f.value, '—')
         ||CASE WHEN coalesce(v.note,'')<>'' THEN ' — '||v.note ELSE '' END,
       v.id, false
FROM dataops.verdict v
JOIN dataops.extraction_field f ON f.id=v.extraction_field_id
JOIN dataops.extraction ex ON ex.id=f.extraction_id
JOIN dataops.artifact a ON a.id=ex.artifact_id
WHERE NOT EXISTS (SELECT 1 FROM dataops.dossier_entry e WHERE e.verdict_id=v.id);

-- status: the close/commit decision
INSERT INTO dataops.dossier_entry (dossier_id, at, kind, actor_kind, text, body, visible_to_melder)
SELECT d.id, coalesce(d.outcome_at, now()), 'status', 'reviewer',
       CASE d.outcome
         WHEN 'accepted' THEN CASE WHEN d.inquiry_id IS NOT NULL THEN 'Overgenomen als rapportage' ELSE 'Afgehandeld' END
         WHEN 'no_data' THEN 'Gesloten: geen funderingsgegevens'
         WHEN 'duplicate' THEN 'Gesloten als duplicaat'
         ELSE 'Afgewezen' END
         ||CASE WHEN coalesce(d.outcome_note,'')<>'' AND d.outcome_note NOT LIKE 'Overgenomen als rapportage #%' THEN ' — '||d.outcome_note ELSE '' END,
       jsonb_build_object('outcome', d.outcome, 'inquiry_id', d.inquiry_id, 'backfilled', true),
       true
FROM dataops.dossier d
WHERE d.outcome IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dataops.dossier_entry e WHERE e.dossier_id=d.id AND e.kind='status');

-- mails already sent (dossier_mail is the send log)
INSERT INTO dataops.dossier_entry (dossier_id, at, kind, actor_kind, actor, text, visible_to_melder)
SELECT m.dossier_id, m.sent_at, 'status', 'system', 'resend',
       CASE m.kind WHEN 'received' THEN 'Ontvangstbevestiging gemaild' ELSE 'Uitkomst gemaild' END, true
FROM dataops.dossier_mail m
WHERE m.status='sent' AND m.sent_at IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dataops.dossier_entry e WHERE e.dossier_id=m.dossier_id AND e.kind='status' AND e.actor='resend' AND e.at=m.sent_at);

SELECT kind, count(*) FROM dataops.dossier_entry GROUP BY 1 ORDER BY 1;
COMMIT;
