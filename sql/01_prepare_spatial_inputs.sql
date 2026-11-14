-- Core preparatory operations that do not select conflicting stops.
-- Run once with ON_ERROR_STOP. Original names, coordinates and rows are preserved.
-- The all-bus pair table is NOT the final Greater Melbourne spatial stop layer.
BEGIN;
DO $$
BEGIN
  IF to_regclass('ptv.mb2021_mel') IS NOT NULL
     OR to_regclass('ptv.bus_stop_route_pairs') IS NOT NULL
     OR EXISTS(SELECT 1 FROM information_schema.columns
               WHERE table_schema='ptv' AND table_name='stops' AND column_name='geom') THEN
    RAISE EXCEPTION 'Preparation targets already exist: inspect rather than overwrite';
  END IF;
  IF (SELECT count(*) FROM ptv.mb_2021)<>368286
     OR (SELECT count(*) FROM ptv.stops)<>27821 THEN
    RAISE EXCEPTION 'Unexpected source count';
  END IF;
  IF EXISTS(SELECT 1 FROM ptv.stops WHERE stop_lat IS NULL OR stop_lon IS NULL
            OR stop_lat NOT BETWEEN -90 AND 90 OR stop_lon NOT BETWEEN -180 AND 180) THEN
    RAISE EXCEPTION 'Unusable source stop coordinates';
  END IF;
END $$;

CREATE TABLE ptv.mb2021_mel AS
SELECT * FROM ptv.mb_2021 WHERE gcc_name21='Greater Melbourne';
CREATE UNIQUE INDEX mba_mb2021_mel_code_idx ON ptv.mb2021_mel(mb_code21);
CREATE INDEX mba_mb2021_mel_geom_gix ON ptv.mb2021_mel USING gist(geom);
COMMENT ON TABLE ptv.mb2021_mel IS 'Exact Greater Melbourne subset of original ASGS 2021 mesh blocks; original AREASQKM21 retained.';

ALTER TABLE ptv.stops ADD COLUMN geom geometry(Point,7844);
UPDATE ptv.stops
SET geom=ST_Transform(
    ST_SetSRID(ST_MakePoint(stop_lon::double precision,stop_lat::double precision),4326),
    7844
);
CREATE INDEX mba_stops_geom_gix ON ptv.stops USING gist(geom);
COMMENT ON COLUMN ptv.stops.geom IS 'GDA2020 point transformed from original GTFS WGS84 lon/lat; duplicate source IDs remain unresolved and original coordinate columns are unchanged.';

CREATE TABLE ptv.bus_stop_route_pairs AS
SELECT DISTINCT st.stop_id,r.route_id
FROM ptv.stop_times st
JOIN ptv.trips t ON t.trip_id=st.trip_id
JOIN ptv.routes r ON r.route_id=t.route_id
WHERE r.route_type=3;
CREATE UNIQUE INDEX mba_bus_stop_route_pair_idx ON ptv.bus_stop_route_pairs(stop_id,route_id);
COMMENT ON TABLE ptv.bus_stop_route_pairs IS 'All source bus stop-ID/route-ID pairs, route_type=3. Nonspatial; no conflicting coordinate candidates have been chosen. Not the final stops_routes_mel layer.';

DO $$
BEGIN
  IF (SELECT count(*) FROM ptv.mb2021_mel)<>59483
     OR EXISTS(SELECT 1 FROM ptv.mb2021_mel WHERE geom IS NULL OR NOT ST_IsValid(geom) OR ST_SRID(geom)<>7844) THEN
    RAISE EXCEPTION 'Greater Melbourne source subset verification failed';
  END IF;
  IF (SELECT count(*) FROM ptv.stops)<>27821
     OR EXISTS(SELECT 1 FROM ptv.stops WHERE geom IS NULL OR NOT ST_IsValid(geom) OR ST_SRID(geom)<>7844) THEN
    RAISE EXCEPTION 'Stop geometry verification failed';
  END IF;
END $$;
ANALYZE ptv.mb2021_mel;
ANALYZE ptv.stops;
ANALYZE ptv.bus_stop_route_pairs;
COMMIT;
