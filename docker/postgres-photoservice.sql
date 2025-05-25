CREATE USER photoservice WITH PASSWORD 'Passw0rd!';
CREATE DATABASE photoservice WITH OWNER photoservice;

\connect photoservice

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE photo (id INT, name VARCHAR(50), price NUMERIC(5, 2), image BYTEA, CONSTRAINT photo_pk PRIMARY KEY (id));

INSERT INTO photo (id, name, price) VALUES ( 1, 'A6407344-2048.jpg', 12.95);
INSERT INTO photo (id, name, price) VALUES ( 2, 'A6407354-2048.jpg', 11.95);
INSERT INTO photo (id, name, price) VALUES ( 3, 'A6407362-2048.jpg', 10.95);
INSERT INTO photo (id, name, price) VALUES ( 4, 'A6407374-2048.jpg',  9.95);
INSERT INTO photo (id, name, price) VALUES ( 5, 'A6407376-2048.jpg',  9.95);
INSERT INTO photo (id, name, price) VALUES ( 6, 'A6407391-2048.jpg', 25.95);
INSERT INTO photo (id, name, price) VALUES ( 7, 'A6407395-2048.jpg', 24.95);
INSERT INTO photo (id, name, price) VALUES ( 8, 'A6407398-2048.jpg', 23.95);
INSERT INTO photo (id, name, price) VALUES ( 9, 'A6407406-2048.jpg', 22.95);
INSERT INTO photo (id, name, price) VALUES (10, 'A6407411-2048.jpg', 21.95);
INSERT INTO photo (id, name, price) VALUES (11, 'A6407417-2048.jpg', 13.95);
INSERT INTO photo (id, name, price) VALUES (12, 'A6407421-2048.jpg', 14.95);
INSERT INTO photo (id, name, price) VALUES (13, 'A6407424-2048.jpg', 16.95);
INSERT INTO photo (id, name, price) VALUES (14, 'A6407427-2048.jpg', 19.95);
INSERT INTO photo (id, name, price) VALUES (15, 'A6407429-2048.jpg', 39.95);
INSERT INTO photo (id, name, price) VALUES (16, 'A6407430-2048.jpg', 24.95);
INSERT INTO photo (id, name, price) VALUES (17, 'A6407432-2048.jpg', 42.95);
INSERT INTO photo (id, name, price) VALUES (18, 'A6407433-2048.jpg', 26.95);
INSERT INTO photo (id, name, price) VALUES (19, 'A6407436-2048.jpg', 23.95);
INSERT INTO photo (id, name, price) VALUES (20, 'A6407439-2048.jpg', 12.95);
INSERT INTO photo (id, name, price) VALUES (21, 'A6407442-2048.jpg', 11.95);
INSERT INTO photo (id, name, price) VALUES (22, 'A6407446-2048.jpg', 10.95);
INSERT INTO photo (id, name, price) VALUES (23, 'A6407453-2048.jpg',  9.95);
INSERT INTO photo (id, name, price) VALUES (24, 'A6407458-2048.jpg',  8.95);

CREATE TABLE customer (id INT, firstname VARCHAR(50), surname VARCHAR(50), city VARCHAR(50), email VARCHAR(200), CONSTRAINT customer_pk PRIMARY KEY (id));
CREATE TABLE order_header (id INT, customer_id INT, created_at TIMESTAMP(3), updated_at TIMESTAMP(3), payment_uuid UUID, shipment_uuid UUID, CONSTRAINT order_header_pk PRIMARY KEY (id));
CREATE TABLE order_detail (order_id INT, photo_id INT, quantity INT, price NUMERIC(7, 2), CONSTRAINT order_detail_pk PRIMARY KEY (order_id, photo_id));
CREATE TABLE order_event (id SERIAL, order_id INT, updated_at TIMESTAMP(3), payment_uuid UUID, shipment_uuid UUID, CONSTRAINT order_event_pk PRIMARY KEY (id));

ALTER TABLE photo OWNER TO photoservice;
ALTER TABLE customer OWNER TO photoservice;
ALTER TABLE order_header OWNER TO photoservice;
ALTER TABLE order_detail OWNER TO photoservice;
ALTER TABLE order_event OWNER TO photoservice;
