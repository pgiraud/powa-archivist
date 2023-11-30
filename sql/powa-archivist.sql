-- General setup
\set SHOW_CONTEXT never

--Setup extension
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION btree_gist;
CREATE SCHEMA "PoWA";
CREATE EXTENSION powa WITH SCHEMA "PoWA";

-- Check the relations that aren't dumped
WITH ext AS (
    SELECT c.oid, c.relname
    FROM pg_depend d
    JOIN pg_extension e ON d.refclassid = 'pg_extension'::regclass
        AND e.oid = d.refobjid
        AND e.extname = 'powa'
    JOIN pg_class c ON d.classid = 'pg_class'::regclass
        AND c.oid = d.objid
),
dmp AS (
    SELECT unnest(extconfig) AS oid
    FROM pg_extension
    WHERE extname = 'powa'
)
SELECT ext.relname
FROM ext
LEFT JOIN dmp USING (oid)
WHERE dmp.oid IS NULL
ORDER BY ext.relname::text COLLATE "C";

-- Check for object that aren't in the "PoWA" schema
WITH ext AS (
    SELECT pg_describe_object(classid, objid, objsubid) AS descr
    FROM pg_depend d
    JOIN pg_extension e ON d.refclassid = 'pg_extension'::regclass
        AND e.oid = d.refobjid
        AND e.extname = 'powa'
)
SELECT descr
FROM ext
WHERE descr NOT LIKE '%"PoWA"%'
ORDER BY descr COLLATE "C";

-- Aggregate data every 5 snapshots
SET powa.coalesce = 5;

-- Test created ojects
SELECT * FROM "PoWA".powa_functions ORDER BY module, operation;

-- test C SRFs
SELECT COUNT(*) = 0
FROM pg_database,
LATERAL "PoWA".powa_stat_user_functions(oid) f
WHERE datname = current_database();

-- on pg15+ the function is a no-op, and this function will be deprecated soon
-- anyway
SELECT COUNT(*) >= 0
FROM pg_database,
LATERAL "PoWA".powa_stat_all_rel(oid)
WHERE datname = current_database();

-- Test snapshot
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_user_functions_history_current;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_all_relations_history_current;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_statements_history_current;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_statements_history_current_db;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_user_functions_history;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_all_relations_history;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_statements_history;
SELECT 1, COUNT(*) = 0 FROM "PoWA".powa_statements_history;

SELECT "PoWA".powa_take_snapshot();

SELECT 2, COUNT(*) >= 0 FROM "PoWA".powa_user_functions_history_current;
SELECT 2, COUNT(*) >= 0 FROM "PoWA".powa_all_relations_history_current;
SELECT 2, COUNT(*) > 0 FROM "PoWA".powa_statements_history_current;
SELECT 2, COUNT(*) > 0 FROM "PoWA".powa_statements_history_current_db;
SELECT 2, COUNT(*) >= 0 FROM "PoWA".powa_user_functions_history;
SELECT 2, COUNT(*) = 0 FROM "PoWA".powa_all_relations_history;
SELECT 2, COUNT(*) = 0 FROM "PoWA".powa_statements_history;
SELECT 2, COUNT(*) = 0 FROM "PoWA".powa_statements_history;

SELECT "PoWA".powa_take_snapshot();
SELECT "PoWA".powa_take_snapshot();
SELECT "PoWA".powa_take_snapshot();
-- This snapshot will trigger the aggregate
SELECT "PoWA".powa_take_snapshot();

SELECT 3, COUNT(*) >= 0 FROM "PoWA".powa_user_functions_history_current;
SELECT 3, COUNT(*) >= 0 FROM "PoWA".powa_all_relations_history_current;
SELECT 3, COUNT(*) > 0 FROM "PoWA".powa_statements_history_current;
SELECT 3, COUNT(*) > 0 FROM "PoWA".powa_statements_history_current_db;
SELECT 3, COUNT(*) >= 0 FROM "PoWA".powa_user_functions_history;
SELECT 3, COUNT(*) >= 0 FROM "PoWA".powa_all_relations_history;
SELECT 3, COUNT(*) > 0 FROM "PoWA".powa_statements_history;
SELECT 3, COUNT(*) > 0 FROM "PoWA".powa_statements_history;

-- Test reset function
SELECT * from "PoWA".powa_reset(0);

SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_user_functions_history_current;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_all_relations_history_current;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_statements_history_current;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_statements_history_current_db;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_user_functions_history;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_all_relations_history;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_statements_history;
SELECT 4, COUNT(*) = 0 FROM "PoWA".powa_statements_history;

-- Check API
SELECT "PoWA".powa_register_server(hostname => '127.0.0.1',
    extensions => '{pg_qualstats}');
SELECT COUNT(*) FROM "PoWA".powa_servers;
SELECT hostname FROM "PoWA".powa_servers WHERE id = 1;

-- Check missing powa_statements FK for pg_qualstats doesn't prevent snapshot
INSERT INTO "PoWA".powa_qualstats_src_tmp(srvid, ts, uniquequalnodeid, dbid, userid,
    qualnodeid, occurences, execution_count, nbfiltered,
    mean_err_estimate_ratio, mean_err_estimate_num,
    queryid, constvalues, quals)
    SELECT 1, now(), 1, 1, 1,
        1, 1000, 1, 0,
        0, 0,
        123456789, '{}', ARRAY[(1259,1,607,'i')::"PoWA".qual_type];
SELECT count(*) FROM "PoWA".powa_qualstats_src_tmp;
SELECT "PoWA".powa_qualstats_snapshot(1);
SELECT count(*) FROM "PoWA".powa_qualstats_src_tmp;
SELECT count(*) FROM "PoWA".powa_qualstats_quals_history_current WHERE srvid = 1;

-- Check snapshot of regular quals
INSERT INTO "PoWA".powa_databases(srvid, oid, datname, dropped)
    VALUES (1, 16384, 'postgres', NULL);
INSERT INTO "PoWA".powa_statements(srvid, queryid, dbid, userid, query)
    VALUES(1, 123456789, 16384, 10, 'query with qual');
INSERT INTO "PoWA".powa_qualstats_src_tmp(srvid, ts, uniquequalnodeid, dbid, userid,
    qualnodeid, occurences, execution_count, nbfiltered,
    mean_err_estimate_ratio, mean_err_estimate_num,
    queryid, constvalues, quals)
    SELECT 1, now(), 1, 16384, 10,
        1, 1000, 1, 0,
        0, 0,
        123456789, '{}', ARRAY[(1259,1,607,'i')::"PoWA".qual_type];
SELECT count(*) FROM "PoWA".powa_qualstats_src_tmp;
SELECT "PoWA".powa_qualstats_snapshot(1);
SELECT count(*) FROM "PoWA".powa_qualstats_src_tmp;
SELECT count(*) FROM "PoWA".powa_qualstats_quals_history_current WHERE srvid = 1;

-- activate / deactivate extension
SELECT * FROM "PoWA".powa_functions ORDER BY srvid, module, operation, function_name;
SELECT * FROM "PoWA".powa_activate_extension(1, 'pg_stat_kcache');
SELECT * FROM "PoWA".powa_activate_extension(1, 'some_extension');
SELECT * FROM "PoWA".powa_functions ORDER BY srvid, module, operation, function_name;
SELECT * FROM "PoWA".powa_deactivate_extension(1, 'pg_stat_kcache');
SELECT * FROM "PoWA".powa_deactivate_extension(1, 'some_extension');
SELECT * FROM "PoWA".powa_functions ORDER BY srvid, module, operation, function_name;

SELECT alias FROM "PoWA".powa_servers WHERE id = 1;
SELECT * FROM "PoWA".powa_configure_server(0, '{"somekey": "someval"}');
SELECT * FROM "PoWA".powa_configure_server(1, '{"somekey": "someval"}');
SELECT * FROM "PoWA".powa_configure_server(1, '{"alias": "test server"}');

SELECT alias FROM "PoWA".powa_servers WHERE id = 1;

-- Test reset function
SELECT * from "PoWA".powa_reset(1);

-- Check remote server removal
DELETE FROM "PoWA".powa_servers WHERE id = 1;
