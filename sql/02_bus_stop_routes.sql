-- Stage (core): Greater Melbourne bus stops and their routes
-- 1) One point per bus stop ID. 138 IDs appear twice in stops.txt (same stop,
--    name with/without suburb, <= 96 m apart), so candidates are collapsed
--    to their centroid and the longer (suburb-qualified) name is kept.
DROP TABLE IF EXISTS ptv.bus_stops_mel CASCADE;
CREATE TABLE ptv.bus_stops_mel AS
WITH bus_ids AS (                       -- stop IDs used by route_type = 3 trips
    SELECT DISTINCT stop_id FROM ptv.bus_stop_route_pairs
), one_point AS (
    SELECT s.stop_id,
           (array_agg(s.stop_name ORDER BY length(s.stop_name) DESC))[1] AS stop_name,
           count(*) AS source_rows,
           ST_Centroid(ST_Collect(s.geom))::geometry(Point,7844) AS geom
    FROM ptv.stops s JOIN bus_ids b USING (stop_id)
    GROUP BY s.stop_id
)
SELECT DISTINCT ON (p.stop_id)          -- keep stops inside Greater Melbourne MBs
       p.stop_id, p.stop_name, p.source_rows, m.mb_code21, m.mb_cat21,
       l.lga_name_2021 AS lga_name, a.sal_name_2021 AS suburb, p.geom
FROM one_point p
JOIN ptv.mb2021_mel m ON ST_Intersects(m.geom, p.geom)
JOIN ptv.lga_2021 l ON l.mb_code_2021 = m.mb_code21
JOIN ptv.sal_2021 a ON a.mb_code_2021 = m.mb_code21
ORDER BY p.stop_id, m.mb_code21;
CREATE UNIQUE INDEX ON ptv.bus_stops_mel (stop_id);
CREATE INDEX ON ptv.bus_stops_mel USING gist (geom);

-- 2) Required table: one row per bus stop x route (route_type = 3 only)
DROP TABLE IF EXISTS ptv.stops_routes_mel;
CREATE TABLE ptv.stops_routes_mel AS
SELECT DISTINCT
       b.stop_id,
       b.stop_name,
       b.geom,                                   -- GDA2020 (SRID 7844)
       ST_Y(b.geom) AS latitude, ST_X(b.geom) AS longitude,
       r.route_short_name AS route_number,
       r.route_long_name  AS route_name,
       'Bus'::text        AS vehicle_type
FROM ptv.bus_stops_mel b
JOIN ptv.bus_stop_route_pairs p ON p.stop_id = b.stop_id
JOIN ptv.routes r ON r.route_id = p.route_id
WHERE r.route_type = 3;
CREATE INDEX ON ptv.stops_routes_mel USING gist (geom);
ANALYZE ptv.bus_stops_mel; ANALYZE ptv.stops_routes_mel;
