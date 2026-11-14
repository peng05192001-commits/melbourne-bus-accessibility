-- Stage, Q8. Weekend comparison: same method as stop_weekday_service,
-- for Saturday 17 and Sunday 18 June 2023 (the weekend before the selected Wednesday).
-- The following weekend (24-25 June) is not used: many operators' calendars end on
-- 23 June 2023, so bus trips in the feed drop sharply from 24 June (check below).
-- Check: bus trips per day, 17-28 June 2023 (feed coverage)
WITH d AS (SELECT generate_series(DATE '2023-06-17', DATE '2023-06-28', interval '1 day')::date AS day),
act AS (
    SELECT d.day, c.service_id FROM d JOIN ptv.calendar c
      ON d.day BETWEEN c.start_date AND c.end_date
     AND CASE extract(isodow FROM d.day) WHEN 1 THEN c.monday WHEN 2 THEN c.tuesday
         WHEN 3 THEN c.wednesday WHEN 4 THEN c.thursday WHEN 5 THEN c.friday
         WHEN 6 THEN c.saturday ELSE c.sunday END = 1
    UNION
    SELECT cd.date, cd.service_id FROM ptv.calendar_dates cd JOIN d ON d.day = cd.date
    WHERE cd.exception_type = 1
    EXCEPT
    SELECT cd.date, cd.service_id FROM ptv.calendar_dates cd JOIN d ON d.day = cd.date
    WHERE cd.exception_type = 2
)
SELECT a.day, to_char(a.day, 'Dy') AS dow, count(*) AS bus_trips
FROM act a JOIN ptv.trips t ON t.service_id = a.service_id
JOIN ptv.routes r ON r.route_id = t.route_id AND r.route_type = 3
GROUP BY 1, 2 ORDER BY 1;

DROP TABLE IF EXISTS ptv.stop_weekend_service;
CREATE TABLE ptv.stop_weekend_service AS
WITH d(day) AS (VALUES (DATE '2023-06-17'), (DATE '2023-06-18')),
active AS (
    SELECT d.day, c.service_id FROM d JOIN ptv.calendar c
      ON d.day BETWEEN c.start_date AND c.end_date
     AND CASE extract(isodow FROM d.day) WHEN 6 THEN c.saturday ELSE c.sunday END = 1
    UNION
    SELECT cd.date, cd.service_id FROM ptv.calendar_dates cd JOIN d ON d.day = cd.date
    WHERE cd.exception_type = 1
    EXCEPT
    SELECT cd.date, cd.service_id FROM ptv.calendar_dates cd JOIN d ON d.day = cd.date
    WHERE cd.exception_type = 2
)
SELECT st.stop_id,
       count(*) FILTER (WHERE a.day = DATE '2023-06-17') AS sat_departures,
       count(*) FILTER (WHERE a.day = DATE '2023-06-18') AS sun_departures
FROM ptv.stop_times st
JOIN ptv.trips t  ON t.trip_id = st.trip_id
JOIN active a     ON a.service_id = t.service_id
JOIN ptv.routes r ON r.route_id = t.route_id AND r.route_type = 3
WHERE coalesce(st.pickup_type, 0) <> 1
  AND st.stop_id IN (SELECT stop_id FROM ptv.bus_stops_mel)
GROUP BY st.stop_id;
CREATE UNIQUE INDEX ON ptv.stop_weekend_service (stop_id);

-- Weekday, Saturday and Sunday departures per stop (MGA55 points for distance queries)
DROP TABLE IF EXISTS ptv.bus_stops_week;
CREATE TABLE ptv.bus_stops_week AS
SELECT g.stop_id, g.lga_name, g.departures AS wed_dep,
       coalesce(e.sat_departures,0) AS sat_dep, coalesce(e.sun_departures,0) AS sun_dep, g.geom
FROM ptv.bus_stops_mga g LEFT JOIN ptv.stop_weekend_service e USING (stop_id);
CREATE INDEX ON ptv.bus_stops_week USING gist (geom);
ANALYZE ptv.bus_stops_week;

-- Residential MBs: scheduled stop departures within 400 m on each day
DROP TABLE IF EXISTS ptv.res_mb_week;
CREATE TABLE ptv.res_mb_week AS
SELECT m.mb_code21, m.lga_name, m.est_residents, m.nearest_stop_m,
       c.wed_400m, c.sat_400m, c.sun_400m,
       ST_Distance(ST_Transform(ST_PointOnSurface(m.geom),7855),
         ST_Transform(ST_SetSRID(ST_MakePoint(144.9632,-37.8138),7844),7855)) / 1000 AS cbd_km
FROM ptv.res_mb_access m
CROSS JOIN LATERAL (SELECT ST_Transform(ST_PointOnSurface(m.geom),7855) AS pt) p
CROSS JOIN LATERAL (
    SELECT coalesce(sum(s.wed_dep),0) AS wed_400m, coalesce(sum(s.sat_dep),0) AS sat_400m,
           coalesce(sum(s.sun_dep),0) AS sun_400m
    FROM ptv.bus_stops_week s WHERE ST_DWithin(s.geom, p.pt, 400)) c;

-- Q8a. Metropolitan totals by day
SELECT count(*) FILTER (WHERE wed_dep > 0) AS stops_served_wed,
       count(*) FILTER (WHERE sat_dep > 0) AS stops_served_sat,
       count(*) FILTER (WHERE sun_dep > 0) AS stops_served_sun,
       sum(wed_dep) AS wed_departures, sum(sat_dep) AS sat_departures, sum(sun_dep) AS sun_departures,
       round(100.0 * sum(sat_dep) / sum(wed_dep), 1) AS sat_pct_of_wed,
       round(100.0 * sum(sun_dep) / sum(wed_dep), 1) AS sun_pct_of_wed
FROM ptv.bus_stops_week;

-- Q8b. Residential MBs with no scheduled stop departure within 400 m, by day
SELECT round(100.0 * avg((wed_400m = 0)::int), 1) AS pct_mb_none_wed,
       round(100.0 * avg((sat_400m = 0)::int), 1) AS pct_mb_none_sat,
       round(100.0 * avg((sun_400m = 0)::int), 1) AS pct_mb_none_sun,
       round(sum(est_residents) FILTER (WHERE sun_400m = 0 AND wed_400m > 0)) AS est_res_lose_all_sun,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY wed_400m) AS median_wed_400m,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY sat_400m) AS median_sat_400m,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY sun_400m) AS median_sun_400m
FROM ptv.res_mb_week;

-- Q8c. By 10 km ring from the CBD: Sunday service as a share of the weekday
SELECT width_bucket(cbd_km, 0, 50, 5) AS ring, count(*) AS residential_mbs,
       round(100.0 * avg((sun_400m = 0)::int), 1) AS pct_mb_none_sun,
       round(100.0 * sum(sun_400m) / nullif(sum(wed_400m),0), 1) AS sun_pct_of_wed
FROM ptv.res_mb_week GROUP BY 1 ORDER BY 1;

-- Q8d. By LGA: Sunday service relative to the weekday
DROP TABLE IF EXISTS ptv.lga_week;
CREATE TABLE ptv.lga_week AS
SELECT lga_name, count(*) AS res_mbs, round(sum(est_residents)) AS est_residents,
       round(100.0 * avg((wed_400m = 0)::int), 1) AS pct_mb_none_wed,
       round(100.0 * avg((sun_400m = 0)::int), 1) AS pct_mb_none_sun,
       round(100.0 * sum(sat_400m) / nullif(sum(wed_400m),0), 1) AS sat_pct_of_wed,
       round(100.0 * sum(sun_400m) / nullif(sum(wed_400m),0), 1) AS sun_pct_of_wed
FROM ptv.res_mb_week GROUP BY lga_name;
SELECT * FROM ptv.lga_week WHERE res_mbs >= 200 ORDER BY sun_pct_of_wed;
