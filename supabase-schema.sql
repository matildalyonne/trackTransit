-- ============================================================
-- Track Transit - Supabase Schema
-- Run this in your Supabase SQL Editor
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── OWNERS ──────────────────────────────────────────────────
-- Owners use Supabase Auth (email/password).
-- This table stores extra profile data.
CREATE TABLE IF NOT EXISTS owners (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  fleet_name TEXT,
  phone TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── TAXIS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS taxis (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
  plate TEXT NOT NULL UNIQUE,
  route TEXT,
  driver TEXT,
  conductor TEXT,
  status TEXT DEFAULT 'inactive' CHECK (status IN ('active','inactive','maintenance','breakdown')),
  trips_today INT DEFAULT 0,
  lat DOUBLE PRECISION DEFAULT 0.3536,
  lng DOUBLE PRECISION DEFAULT 32.7562,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── DRIVERS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS drivers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,  -- store bcrypt hash; never plaintext
  name TEXT NOT NULL,
  phone TEXT,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── OTP REQUESTS ────────────────────────────────────────────
-- When a driver tries to log in, an OTP row is created.
-- The owner's device reads this and shows the OTP.
CREATE TABLE IF NOT EXISTS otp_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  otp TEXT NOT NULL,             -- 4-digit code
  used BOOLEAN DEFAULT false,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '5 minutes'),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── MAINTENANCE REPORTS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  taxi_id UUID NOT NULL REFERENCES taxis(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES drivers(id),
  type TEXT NOT NULL,
  note TEXT,
  resolved BOOLEAN DEFAULT false,
  resolved_at TIMESTAMPTZ,
  reported_at TIMESTAMPTZ DEFAULT now()
);

-- ── LOCATION UPDATES ────────────────────────────────────────
-- Each driver GPS ping is stored here (and taxi row updated).
CREATE TABLE IF NOT EXISTS location_updates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  taxi_id UUID NOT NULL REFERENCES taxis(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES drivers(id),
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  accuracy REAL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── TRIPS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  taxi_id UUID NOT NULL REFERENCES taxis(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES drivers(id),
  conductor TEXT,
  trip_date DATE DEFAULT CURRENT_DATE,
  logged_at TIMESTAMPTZ DEFAULT now()
);

-- ── ROW LEVEL SECURITY ───────────────────────────────────────
ALTER TABLE owners ENABLE ROW LEVEL SECURITY;
ALTER TABLE taxis ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_requests ENABLE ROW LEVEL SECURITY;

-- Owners can only see and edit their own data
CREATE POLICY "Owner sees own profile" ON owners FOR ALL USING (auth.uid() = id);

CREATE POLICY "Owner sees own taxis" ON taxis FOR ALL USING (auth.uid() = owner_id);

CREATE POLICY "Owner sees own drivers" ON drivers FOR ALL USING (auth.uid() = owner_id);

CREATE POLICY "Owner sees own maintenance" ON maintenance FOR ALL
  USING (taxi_id IN (SELECT id FROM taxis WHERE owner_id = auth.uid()));

CREATE POLICY "Owner sees own trips" ON trips FOR ALL
  USING (taxi_id IN (SELECT id FROM taxis WHERE owner_id = auth.uid()));

CREATE POLICY "Owner sees own location updates" ON location_updates FOR ALL
  USING (taxi_id IN (SELECT id FROM taxis WHERE owner_id = auth.uid()));

CREATE POLICY "Owner sees own OTPs" ON otp_requests FOR ALL USING (auth.uid() = owner_id);

-- ── REALTIME ────────────────────────────────────────────────
-- Enable realtime on location_updates and otp_requests
-- (Do this in Supabase Dashboard → Database → Replication)
-- Tables: location_updates, otp_requests, maintenance

-- ── USEFUL FUNCTIONS ────────────────────────────────────────

-- Daily trips reset (call this via a Supabase cron job at midnight)
CREATE OR REPLACE FUNCTION reset_daily_trips()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE taxis SET trips_today = 0;
END;
$$;

-- Generate OTP function
CREATE OR REPLACE FUNCTION generate_otp(p_driver_id UUID, p_owner_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_otp TEXT;
BEGIN
  -- Invalidate old OTPs for this driver
  UPDATE otp_requests SET used = true WHERE driver_id = p_driver_id AND NOT used;
  -- Generate new 4-digit OTP
  v_otp := LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  INSERT INTO otp_requests (owner_id, driver_id, otp)
  VALUES (p_owner_id, p_driver_id, v_otp);
  RETURN v_otp;
END;
$$;

-- ── SAMPLE DATA (optional, for testing) ─────────────────────
-- Replace 'YOUR_OWNER_UUID' with the UUID from auth.users after signing up

-- INSERT INTO owners (id, name, fleet_name, phone) 
-- VALUES ('YOUR_OWNER_UUID', 'Joseph Muwonge', 'Muwonge Taxis', '+256700000000');

-- INSERT INTO taxis (owner_id, plate, route, driver, conductor, status, lat, lng)
-- VALUES 
--   ('YOUR_OWNER_UUID', 'UAX 123B', 'Mukono–Kampala', 'John Ssempala', 'Moses Katende', 'active', 0.3536, 32.7562),
--   ('YOUR_OWNER_UUID', 'UBF 456K', 'Mukono–Jinja', 'David Wasswa', 'Peter Mwesige', 'active', 0.3612, 32.7490),
--   ('YOUR_OWNER_UUID', 'UAT 789M', 'Mukono–Seeta', 'Robert Kizito', 'Samuel Ouma', 'breakdown', 0.3480, 32.7640);
