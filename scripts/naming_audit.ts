// Naming convention audit. Reproducible — re-run after any rename migration
// to confirm no new drift was introduced.
//
// When auditing SQL callers around a column rename (the C# monolith is retired), ALSO grep for
// `= <alias>.<col>` (JOIN-on-right) patterns, not just `<alias>.<col>`
// standalone. We learned this the hard way during Phase D — three JOIN
// clauses survived a clean grep because the column was on the right
// side of an equality.
import { sql } from "../src/db.ts";

const SCHEMAS = ["application", "report", "geocoder", "data", "maplayer"];

try {
  console.log("=== FK columns missing _id suffix ===");
  const fkCols = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      a.attname AS column,
      cn.nspname AS ref_schema,
      cf.relname AS ref_table
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_class cf ON cf.oid = con.confrelid
    JOIN pg_namespace cn ON cn.oid = cf.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
    WHERE con.contype = 'f'
      AND n.nspname = ANY(${SCHEMAS})
      AND a.attname NOT LIKE '%\\_id' ESCAPE '\\'
      AND a.attname NOT IN ('external_id')
      AND array_length(con.conkey, 1) = 1
    ORDER BY n.nspname, c.relname, a.attname;
  `;
  console.log(JSON.stringify(fkCols, null, 2));

  console.log("\n=== Indexes with idx_ prefix (should be _idx suffix) ===");
  const idxPrefix = await sql`
    SELECT schemaname, tablename, indexname
    FROM pg_indexes
    WHERE schemaname = ANY(${SCHEMAS})
      AND indexname LIKE 'idx\\_%' ESCAPE '\\'
    ORDER BY schemaname, tablename, indexname;
  `;
  console.log(JSON.stringify(idxPrefix, null, 2));

  console.log("\n=== Indexes missing table prefix ===");
  const idxNoPrefix = await sql`
    SELECT schemaname, tablename, indexname
    FROM pg_indexes
    WHERE schemaname = ANY(${SCHEMAS})
      AND indexname NOT LIKE tablename || '%'
      AND indexname NOT LIKE 'pg_%'
    ORDER BY schemaname, tablename, indexname;
  `;
  console.log(JSON.stringify(idxNoPrefix, null, 2));

  console.log("\n=== PK constraints not ending in _pkey ===");
  const pkInconsistent = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE con.contype = 'p'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname NOT LIKE '%\\_pkey' ESCAPE '\\'
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(pkInconsistent, null, 2));

  console.log("\n=== FK constraints ending in _fk (should be _fkey) ===");
  const fkInconsistent = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE con.contype = 'f'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname LIKE '%\\_fk' ESCAPE '\\'
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(fkInconsistent, null, 2));

  console.log("\n=== FK constraints with wrong/missing table prefix ===");
  const fkWrongPrefix = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE con.contype = 'f'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname NOT LIKE c.relname || '\\_%' ESCAPE '\\'
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(fkWrongPrefix, null, 2));

  console.log("\n=== FK constraints with no column name (too generic) ===");
  const fkGeneric = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint,
      a.attname AS column
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
    WHERE con.contype = 'f'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname NOT LIKE '%' || a.attname || '%'
      AND array_length(con.conkey, 1) = 1
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(fkGeneric, null, 2));

  console.log("\n=== UNIQUE constraints not ending in _key ===");
  const uniqueInconsistent = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE con.contype = 'u'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname NOT LIKE '%\\_key' ESCAPE '\\'
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(uniqueInconsistent, null, 2));

  console.log("\n=== CHECK constraints not ending in _check or _chk ===");
  const checkInconsistent = await sql`
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      con.conname AS constraint
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE con.contype = 'c'
      AND n.nspname = ANY(${SCHEMAS})
      AND con.conname NOT LIKE '%\\_check' ESCAPE '\\'
      AND con.conname NOT LIKE '%\\_chk' ESCAPE '\\'
      AND con.conname NOT LIKE '%\\_excl' ESCAPE '\\'
    ORDER BY n.nspname, c.relname;
  `;
  console.log(JSON.stringify(checkInconsistent, null, 2));
} catch (error) {
  console.error(error);
} finally {
  await sql.end();
}
