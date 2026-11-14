-- Stage: Bus accessibility of residential Melbourne (analysis queries)

-- Q1. Metropolitan overview
SELECT (SELECT count(*) FROM ptv.bus_stops_mel)                         AS bus_stops,
       (SELECT count(DISTINCT coalesce(nullif(route_number,''), route_name))
          FROM ptv.stops_routes_mel)                                    AS bus_routes,
       (SELECT sum(departures) FROM ptv.stop_weekday_service)           AS weekday_departures,
       round(4917750.0 / (SELECT count(*) FROM ptv.bus_stops_mel), 0)   AS residents_per_stop,
       count(*)                                                         AS residential_mbs,
       round(100.0 * avg((nearest_stop_m <= 400)::int), 1)              AS pct_mb_within_400m,
       round(sum(est_residents) FILTER (WHERE nearest_stop_m > 400))    AS est_residents_beyond_400m,
       round(sum(est_residents) FILTER (WHERE nearest_stop_m > 800))    AS est_residents_beyond_800m,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY nearest_stop_m)::numeric) AS median_walk_m
FROM ptv.res_mb_access;

-- Q2. Distance bands to the nearest bus stop
SELECT CASE WHEN nearest_stop_m <= 200 THEN '1: 0-200 m'
            WHEN nearest_stop_m <= 400 THEN '2: 200-400 m'
            WHEN nearest_stop_m <= 800 THEN '3: 400-800 m'
            ELSE '4: over 800 m' END                      AS walk_band,
       count(*)                                           AS residential_mbs,
       round(sum(est_residents))                          AS est_residents,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ptv.res_mb_access GROUP BY 1 ORDER BY 1;

-- Q3. LGA summary table (also the map layer)
DROP TABLE IF EXISTS ptv.lga_res_access;
CREATE TABLE ptv.lga_res_access AS
WITH r AS (
    SELECT lga_name,
           count(*)                                    AS res_mbs,
           round(sum(est_residents))                   AS est_residents,
           round(sum(areasqkm21), 1)                   AS res_area_km2,
           round(100.0 * avg((nearest_stop_m <= 400)::int), 1) AS pct_mb_400m,
           round(100.0 * avg((nearest_stop_m > 800)::int), 1)  AS pct_mb_over_800m,
           round(sum(est_residents) FILTER (WHERE nearest_stop_m > 400)) AS est_res_beyond_400m,
           round(percentile_cont(0.5) WITHIN GROUP (ORDER BY nearest_stop_m)::numeric) AS median_walk_m,
           round(percentile_cont(0.5) WITHIN GROUP (ORDER BY departures_400m)::numeric) AS median_dep_400m
    FROM ptv.res_mb_access GROUP BY lga_name
), s AS (
    SELECT b.lga_name, count(*) AS bus_stops,
           sum(coalesce(w.departures,0)) AS weekday_departures
    FROM ptv.bus_stops_mel b LEFT JOIN ptv.stop_weekday_service w USING (stop_id)
    GROUP BY b.lga_name
), g AS (
    SELECT l.lga_name_2021 AS lga_name, ST_Multi(ST_Union(m.geom))::geometry(MultiPolygon,7844) AS geom
    FROM ptv.mb2021_mel m JOIN ptv.lga_2021 l ON l.mb_code_2021 = m.mb_code21
    GROUP BY 1
)
SELECT r.*, coalesce(s.bus_stops,0) AS bus_stops,
       round(coalesce(s.bus_stops,0) / r.res_area_km2, 1)               AS stops_per_res_km2,
       coalesce(s.weekday_departures,0)                                 AS weekday_departures,
       round(1000.0 * coalesce(s.weekday_departures,0) / r.est_residents, 1) AS departures_per_1000_res,
       g.geom
FROM r LEFT JOIN s USING (lga_name) JOIN g USING (lga_name);
CREATE INDEX ON ptv.lga_res_access USING gist (geom);

SELECT lga_name, res_mbs, est_residents, bus_stops, stops_per_res_km2, pct_mb_400m,
       pct_mb_over_800m, median_walk_m, median_dep_400m, departures_per_1000_res
FROM ptv.lga_res_access ORDER BY pct_mb_400m DESC;

-- Q4. Coverage and service level by distance from the Melbourne CBD (GPO)
SELECT width_bucket(ST_Distance(ST_Transform(ST_PointOnSurface(geom),7855),
         ST_Transform(ST_SetSRID(ST_MakePoint(144.9632, -37.8138),7844),7855)) / 1000, 0, 50, 5) AS ring,
       count(*)                                              AS residential_mbs,
       round(100.0 * avg((nearest_stop_m <= 400)::int), 1)   AS pct_mb_400m,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY departures_400m)::numeric) AS median_dep_400m
FROM ptv.res_mb_access GROUP BY 1 ORDER BY 1;

-- Q5. Suburbs with the largest residential gaps (> 800 m from any bus stop)
SELECT suburb, lga_name, count(*) AS gap_mbs, round(sum(est_residents)) AS est_residents
FROM ptv.res_mb_access WHERE nearest_stop_m > 800
GROUP BY suburb, lga_name ORDER BY gap_mbs DESC LIMIT 10;

-- Q6. Service intensity inside the 400 m catchment (weekday departures)
SELECT CASE WHEN departures_400m = 0    THEN '1: no service'
            WHEN departures_400m < 100  THEN '2: 1-99 (low)'
            WHEN departures_400m < 300  THEN '3: 100-299 (medium)'
            ELSE '4: 300+ (high)' END                       AS service_band,
       count(*) AS residential_mbs, round(sum(est_residents)) AS est_residents,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)   AS pct
FROM ptv.res_mb_access GROUP BY 1 ORDER BY 1;

-- Q7. Busiest bus stops (weekday departures)
SELECT b.stop_name, b.suburb, w.departures, w.routes_running
FROM ptv.stop_weekday_service w JOIN ptv.bus_stops_mel b USING (stop_id)
ORDER BY w.departures DESC LIMIT 10;
