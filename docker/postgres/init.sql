-- Initialize Spotik database
-- This script runs when the PostgreSQL container starts for the first time

-- Create the database user if it doesn't exist
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = 'spotik_user') THEN

      CREATE ROLE spotik_user LOGIN PASSWORD 'spotik_password';
   END IF;
END
$do$;

-- Grant privileges to the user
GRANT ALL PRIVILEGES ON DATABASE spotik TO spotik_user;
GRANT ALL ON SCHEMA public TO spotik_user;

-- Create extensions if they don't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Set timezone
SET timezone = 'UTC';

-- Create indexes for better performance (will be created by migrations, but good to have as backup)
-- These will be created by Laravel migrations, but documented here for reference

-- Performance optimization settings
-- Note: pg_stat_statements requires restart to enable, so we'll skip it for now
-- ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- ALTER SYSTEM SET pg_stat_statements.track = 'all';

-- Basic logging settings
ALTER SYSTEM SET log_statement = 'none';
ALTER SYSTEM SET log_min_duration_statement = 5000;

-- Reload configuration
SELECT pg_reload_conf();