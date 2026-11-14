-- Export the Stage LGA summary (no geometry) as CSV for Figure 3.
-- Run with psql and redirect the output, e.g.
--   docker exec -i postgis psql -U postgres -d gisdb -q < 05_export_lga_summary.sql
--     > data/lga_res_access.csv
COPY (
    SELECT lga_name, res_mbs, est_residents, bus_stops, stops_per_res_km2, pct_mb_400m,
           pct_mb_over_800m, median_walk_m, median_dep_400m, weekday_departures,
           departures_per_1000_res
    FROM ptv.lga_res_access
    ORDER BY lga_name
) TO STDOUT WITH CSV HEADER;
