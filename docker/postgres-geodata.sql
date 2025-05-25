CREATE USER geodata WITH PASSWORD 'Passw0rd!';
CREATE DATABASE geodata WITH OWNER geodata;
\connect geodata
CREATE EXTENSION IF NOT EXISTS postgis;
