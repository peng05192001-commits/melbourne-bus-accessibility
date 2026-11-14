#!/bin/bash
# Run inside the PostGIS container (e.g. docker exec -i postgis bash -s < export_map_layers.sh).
# Exports the four map layers used by build_maps.py into one GeoPackage (CRS 7844).
set -e
OUT=/tmp/accessibility.gpkg
PG="PG:dbname=gisdb user=postgres"
rm -f "$OUT"
ogr2ogr -f GPKG "$OUT" "$PG" -nln lga_res_access -sql "
  SELECT lga_name, res_mbs, est_residents, bus_stops, stops_per_res_km2, pct_mb_400m,
         pct_mb_over_800m, median_walk_m, median_dep_400m, departures_per_1000_res, geom
  FROM ptv.lga_res_access"
ogr2ogr -f GPKG -update "$OUT" "$PG" -nln bus_stops -sql "
  SELECT b.stop_id, b.stop_name, b.suburb, b.lga_name,
         coalesce(w.departures, 0) AS departures,
         coalesce(w.am_peak_departures, 0) AS am_peak, b.geom
  FROM ptv.bus_stops_mel b LEFT JOIN ptv.stop_weekday_service w USING (stop_id)"
ogr2ogr -f GPKG -update "$OUT" "$PG" -nln res_mb_access -sql "
  SELECT mb_code21, suburb, lga_name, round(nearest_stop_m::numeric, 1) AS nearest_stop_m,
         stops_400m, departures_400m,
         CASE WHEN nearest_stop_m <= 200 THEN 1 WHEN nearest_stop_m <= 400 THEN 2
              WHEN nearest_stop_m <= 800 THEN 3 ELSE 4 END AS walk_band,
         geom
  FROM ptv.res_mb_access"
ogr2ogr -f GPKG -update "$OUT" "$PG" -nln gmel_outline -sql "
  SELECT 'Greater Melbourne'::text AS name,
         ST_Multi(ST_Union(geom))::geometry(MultiPolygon, 7844) AS geom
  FROM ptv.lga_res_access"
# then copy to the host: docker cp postgis:/tmp/accessibility.gpkg data/processed/accessibility.gpkg
