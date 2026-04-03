-- DROP EXISTING
DROP VIEW IF EXISTS vw_wet_weather_strategies;
DROP VIEW IF EXISTS vw_dashboard_stats;
DROP PROCEDURE IF EXISTS GenerateSeasonReport;
DROP TRIGGER IF EXISTS trg_validate_fuel;
DROP TRIGGER IF EXISTS trg_audit_simulations;

-- We ignore dropping tables if there's foreign key constraints causing issues, but we can do a clean sweep
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS tire_stints;
DROP TABLE IF EXISTS simulation_audit;
DROP TABLE IF EXISTS simulations;
DROP TABLE IF EXISTS circuits;
DROP TABLE IF EXISTS drivers;
SET FOREIGN_KEY_CHECKS = 1;

CREATE DATABASE IF NOT EXISTS f1_strategy_db;
USE f1_strategy_db;

-- 1. NORMALIZATION & RELATIONAL TABLES
CREATE TABLE drivers (
    driver_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    team_name VARCHAR(100),
    championship_points INT DEFAULT 0
);

CREATE TABLE circuits (
    circuit_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    country VARCHAR(50) NOT NULL,
    base_laps INT,
    avg_track_temp DOUBLE
);

CREATE TABLE simulations (
    simulation_id INT AUTO_INCREMENT PRIMARY KEY,
    driver_id INT,
    circuit_id INT,
    laps INT NOT NULL,
    fuel_load DOUBLE NOT NULL,
    fuel_per_lap DOUBLE,
    weather_condition VARCHAR(30) DEFAULT 'Dry',
    safety_car_prob VARCHAR(30) DEFAULT 'Low',
    strategy_summary VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (driver_id) REFERENCES drivers(driver_id) ON DELETE CASCADE,
    FOREIGN KEY (circuit_id) REFERENCES circuits(circuit_id) ON DELETE SET NULL
);

-- One-To-Many Relationship
CREATE TABLE tire_stints (
    stint_id INT AUTO_INCREMENT PRIMARY KEY,
    simulation_id INT NOT NULL,
    lap_start INT NOT NULL,
    lap_end INT NOT NULL,
    compound_type VARCHAR(20) NOT NULL,
    color_code VARCHAR(10),
    FOREIGN KEY (simulation_id) REFERENCES simulations(simulation_id) ON DELETE CASCADE
);

CREATE TABLE simulation_audit (
    audit_id INT AUTO_INCREMENT PRIMARY KEY,
    simulation_id INT,
    action_type VARCHAR(50),
    action_details VARCHAR(255),
    action_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- SEED DATA
INSERT IGNORE INTO drivers (name, team_name) VALUES 
('max verstappen', 'Red Bull Racing'), 
('lewis hamilton', 'Mercedes'), 
('charles leclerc', 'Ferrari'), 
('lando norris', 'McLaren');

INSERT IGNORE INTO circuits (name, country, base_laps, avg_track_temp) VALUES 
('Monza', 'Italy', 53, 35.5),
('Silverstone', 'UK', 52, 22.0),
('Suzuka', 'Japan', 53, 28.5);

-- 2. ADVANCED TRIGGERS
-- Validation Trigger
DELIMITER //
CREATE TRIGGER trg_validate_fuel 
BEFORE INSERT ON simulations
FOR EACH ROW 
BEGIN
    IF NEW.fuel_load < 3.0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FIA Regulation Violation: Fuel load cannot be less than 3.0 kg!';
    END IF;
END;
//

-- Audit Trigger
CREATE TRIGGER trg_audit_simulations
AFTER INSERT ON simulations
FOR EACH ROW
BEGIN
    INSERT INTO simulation_audit (simulation_id, action_type, action_details) 
    VALUES (NEW.simulation_id, 'INSERT', CONCAT('Simulation generated for driver ID: ', NEW.driver_id, ' with fuel ', NEW.fuel_load));
END;
//
DELIMITER ;


-- 3. SQL VIEWS (Virtual Data Sets)
CREATE VIEW vw_wet_weather_strategies AS
SELECT s.simulation_id, d.name AS driver, s.laps, s.strategy_summary, s.created_at
FROM simulations s
JOIN drivers d ON s.driver_id = d.driver_id
WHERE s.weather_condition = 'Rain';

CREATE VIEW vw_dashboard_stats AS
SELECT d.name AS driver, COUNT(s.simulation_id) as total_simulations, AVG(s.fuel_per_lap) as avg_consumption
FROM drivers d
LEFT JOIN simulations s ON d.driver_id = s.driver_id
GROUP BY d.driver_id;


-- 4. STORED PROCEDURE
DELIMITER //
CREATE PROCEDURE GenerateSeasonReport()
BEGIN
    SELECT d.team_name, SUM(s.laps) as total_simulated_laps, AVG(s.fuel_load) as avg_team_fuel
    FROM drivers d
    JOIN simulations s ON d.driver_id = s.driver_id
    GROUP BY d.team_name
    ORDER BY total_simulated_laps DESC;
END;
//
DELIMITER ;
