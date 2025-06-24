-- Initialize XR Future Forests Lab database with sample data
-- This script sets up the basic tables and inserts some test data

-- Create tables will be handled by SQLAlchemy, but we can insert sample data

-- Insert sample species
INSERT INTO species (name, scientific_name) VALUES 
    ('Oak', 'Quercus robur'),
    ('Pine', 'Pinus sylvestris'),
    ('Beech', 'Fagus sylvatica')
ON CONFLICT (name) DO NOTHING;

-- Insert sample locations
INSERT INTO locations (name, latitude, longitude) VALUES 
    ('Freiburg Forest North', 47.9990, 7.8421),
    ('Black Forest Research Site', 48.0500, 8.2000),
    ('University Campus Grove', 47.9947, 7.8394)
ON CONFLICT DO NOTHING;
