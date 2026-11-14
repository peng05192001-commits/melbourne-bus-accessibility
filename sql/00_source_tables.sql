CREATE EXTENSION IF NOT EXISTS postgis;
-- ten CSV source tables, unchanged source rows.
-- No DROP, TRUNCATE, overwrite, repair, filtering, or inferred foreign keys.
CREATE SCHEMA IF NOT EXISTS ptv;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
             WHERE n.nspname='ptv' AND c.relkind IN ('r','p','f','v','m')) THEN
    RAISE EXCEPTION 'ptv already contains relations: inspect before restoring, do not overwrite';
  END IF;
END $$;
SET LOCAL DateStyle TO 'ISO, YMD';
CREATE TABLE ptv.agency (
  agency_id text, agency_name text, agency_url text, agency_timezone text, agency_lang text
);
CREATE TABLE ptv.calendar (
  service_id text, monday integer, tuesday integer, wednesday integer,
  thursday integer, friday integer, saturday integer, sunday integer,
  start_date date, end_date date
);
CREATE TABLE ptv.calendar_dates (service_id text, date date, exception_type integer);
CREATE TABLE ptv.routes (
  route_id text, agency_id text, route_short_name text, route_long_name text,
  route_type integer, route_color text, route_text_color text
);
CREATE TABLE ptv.stops (
  stop_id text, stop_name text, stop_lat numeric, stop_lon numeric
);
CREATE TABLE ptv.trips (
  route_id text, service_id text, trip_id text, shape_id text,
  trip_headsign text, direction_id integer
);
CREATE TABLE ptv.stop_times (
  trip_id text, arrival_time text, departure_time text, stop_id text,
  stop_sequence integer, stop_headsign text, pickup_type integer,
  drop_off_type integer, shape_dist_traveled numeric
);
CREATE TABLE ptv.shapes (
  shape_id text, shape_pt_lat numeric, shape_pt_lon numeric,
  shape_pt_sequence integer, shape_dist_traveled numeric
);
CREATE TABLE ptv.lga_2021 (
  mb_code_2021 text, lga_code_2021 text, lga_name_2021 text,
  state_code_2021 text, state_name_2021 text, aus_code_2021 text,
  aus_name_2021 text, area_albers_sqkm numeric, asgs_loci_uri_2021 text
);
CREATE TABLE ptv.sal_2021 (
  mb_code_2021 text, sal_code_2021 text, sal_name_2021 text,
  state_code_2021 text, state_name_2021 text, aus_code_2021 text,
  aus_name_2021 text, area_albers_sqkm numeric, asgs_loci_uri_2021 text
);
COMMENT ON TABLE ptv.stop_times IS 'Unfiltered source GTFS source. Times are text to preserve values beyond 24:00:00.';
COMMENT ON TABLE ptv.lga_2021 IS 'Original ASGS 2021 mesh-block-to-LGA allocation CSV; not an LGA polygon layer.';
COMMENT ON TABLE ptv.sal_2021 IS 'Original ASGS 2021 mesh-block-to-SAL allocation CSV; not an SAL polygon layer.';
