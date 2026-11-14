-- Stage (focus area): Residential & Population perspective
-- A) Scheduled stop departures on the selected weekday, 21 June 2023.
-- Whole-feed trip counts on 19-23 June range from 28,106 to 28,580.
DROP TABLE IF EXISTS ptv.stop_weekday_service;
CREATE TABLE ptv.stop_weekday_service AS
WITH active_services AS (
    SELECT service_id FROM ptv.calendar
    WHERE wednesday = 1 AND DATE '2023-06-21' BETWEEN start_date AND end_date
    UNION
    SELECT service_id FROM ptv.calendar_dates
    WHERE date = DATE '2023-06-21' AND exception_type = 1
    EXCEPT
    SELECT service_id FROM ptv.calendar_dates
    WHERE date = DATE '2023-06-21' AND exception_type = 2
)
SELECT st.stop_id,
       count(*) AS departures,                                   -- boardable bus departures per day
       count(*) FILTER (WHERE split_part(st.departure_time,':',1)::int IN (7,8)) AS am_peak_departures,
       count(DISTINCT r.route_short_name || r.route_long_name) AS routes_running
FROM ptv.stop_times st
JOIN ptv.trips t   ON t.trip_id = st.trip_id
JOIN active_services a ON a.service_id = t.service_id
JOIN ptv.routes r  ON r.route_id = t.route_id AND r.route_type = 3
WHERE coalesce(st.pickup_type, 0) <> 1                            -- passengers can board
  AND st.stop_id IN (SELECT stop_id FROM ptv.bus_stops_mel)
GROUP BY st.stop_id;
CREATE UNIQUE INDEX ON ptv.stop_weekday_service (stop_id);

-- B) Bus stops in a metric CRS (GDA2020 / MGA zone 55, EPSG:7855)
DROP TABLE IF EXISTS ptv.bus_stops_mga;
CREATE TABLE ptv.bus_stops_mga AS
SELECT b.stop_id, b.lga_name, coalesce(s.departures,0) AS departures,
       coalesce(s.am_peak_departures,0) AS am_peak_departures,
       ST_Transform(b.geom, 7855)::geometry(Point,7855) AS geom
FROM ptv.bus_stops_mel b LEFT JOIN ptv.stop_weekday_service s USING (stop_id);
CREATE INDEX ON ptv.bus_stops_mga USING gist (geom);
ANALYZE ptv.bus_stops_mga;

-- C) Residential MBs: straight-line distance to nearest stop + service within 400 m
DROP TABLE IF EXISTS ptv.res_mb_access;
CREATE TABLE ptv.res_mb_access AS
SELECT m.mb_code21, m.sa2_name21, l.lga_name_2021 AS lga_name, a.sal_name_2021 AS suburb,
       m.areasqkm21,
       n.nearest_stop_m,
       c.stops_400m, c.departures_400m, c.am_peak_400m,
       m.geom
FROM ptv.mb2021_mel m
JOIN ptv.lga_2021 l ON l.mb_code_2021 = m.mb_code21
JOIN ptv.sal_2021 a ON a.mb_code_2021 = m.mb_code21
CROSS JOIN LATERAL (SELECT ST_Transform(ST_PointOnSurface(m.geom), 7855) AS pt) p
CROSS JOIN LATERAL (                                   -- nearest bus stop (KNN)
    SELECT ST_Distance(s.geom, p.pt) AS nearest_stop_m
    FROM ptv.bus_stops_mga s ORDER BY s.geom <-> p.pt LIMIT 1) n
CROSS JOIN LATERAL (                                   -- stops and departures within 400 m
    SELECT count(*) AS stops_400m,
           coalesce(sum(s.departures),0) AS departures_400m,
           coalesce(sum(s.am_peak_departures),0) AS am_peak_400m
    FROM ptv.bus_stops_mga s WHERE ST_DWithin(s.geom, p.pt, 400)) c
WHERE m.mb_cat21 = 'Residential';
CREATE UNIQUE INDEX ON ptv.res_mb_access (mb_code21);
CREATE INDEX ON ptv.res_mb_access USING gist (geom);

-- D) Population proxy: 4,917,750 residents shared equally across residential MBs
ALTER TABLE ptv.res_mb_access ADD COLUMN est_residents numeric;
UPDATE ptv.res_mb_access
SET est_residents = 4917750.0 / (SELECT count(*) FROM ptv.res_mb_access);
ANALYZE ptv.res_mb_access;
