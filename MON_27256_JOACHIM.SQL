-- =============================================
-- SMART HOME ENERGY MANAGEMENT SYSTEM
-- Complete Database Schema and Implementation
-- =============================================

-- =============================================
-- SECTION 1: TABLE DEFINITIONS (DDL)
-- =============================================

-- USER TABLE - Stores user information
CREATE TABLE "USER" (
    user_id NUMBER PRIMARY KEY,
    name VARCHAR2(50) NOT NULL,
    email VARCHAR2(100) UNIQUE NOT NULL,
    created_at DATE DEFAULT SYSDATE NOT NULL
);

-- HOME TABLE - Stores home/property information linked to users
CREATE TABLE HOME (
    home_id NUMBER PRIMARY KEY,
    address VARCHAR2(150) NOT NULL,
    location VARCHAR2(100) NOT NULL,
    user_id NUMBER NOT NULL,
    CONSTRAINT fk_home_user FOREIGN KEY (user_id) REFERENCES "USER"(user_id)
);

-- APPLIANCE TABLE - Stores smart appliances in each home
CREATE TABLE APPLIANCE (
    appliance_id NUMBER PRIMARY KEY,
    type VARCHAR2(50) NOT NULL,
    brand VARCHAR2(50) NOT NULL,
    status VARCHAR2(20) CHECK (status IN ('ON', 'OFF', 'IDLE')) NOT NULL,
    home_id NUMBER NOT NULL,
    CONSTRAINT fk_appliance_home FOREIGN KEY (home_id) REFERENCES HOME(home_id)
);

-- ENERGY USAGE RECORD TABLE - Stores energy consumption data
CREATE TABLE ENERGY_USAGE_RECORD (
    record_id NUMBER PRIMARY KEY,
    appliance_id NUMBER NOT NULL,
    timestamp DATE NOT NULL,
    energy_consumed_kwh NUMBER(5,2) NOT NULL,
    CONSTRAINT fk_usage_appliance FOREIGN KEY (appliance_id) REFERENCES APPLIANCE(appliance_id)
);

-- HOLIDAYS TABLE - Reference table for business rules and restrictions
CREATE TABLE HOLIDAYS (
    holiday_id NUMBER PRIMARY KEY,
    holiday_name VARCHAR2(100) NOT NULL,
    holiday_date DATE NOT NULL,
    description VARCHAR2(200)
);

-- AUDIT_LOG TABLE - Tracks all system operations for compliance
CREATE TABLE AUDIT_LOG (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id VARCHAR2(30),
    action_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    table_affected VARCHAR2(50),
    operation_type VARCHAR2(20),
    record_id NUMBER,
    status VARCHAR2(20),
    comments VARCHAR2(200)
);

-- =============================================
-- SECTION 2: TABLE MODIFICATIONS (ALTER STATEMENTS)
-- =============================================

-- Modify energy consumption column to support higher precision
ALTER TABLE ENERGY_USAGE_RECORD
MODIFY energy_consumed_kwh NUMBER(7,3);

-- =============================================
-- SECTION 3: STORED PROCEDURES
-- =============================================

-- Procedure to log energy usage records with error handling
CREATE OR REPLACE PROCEDURE log_energy_record (
    p_record_id NUMBER,
    p_appliance_id NUMBER,
    p_energy_kwh NUMBER
) IS
BEGIN
    INSERT INTO ENERGY_USAGE_RECORD (record_id, appliance_id, timestamp, energy_consumed_kwh)
    VALUES (p_record_id, p_appliance_id, SYSDATE, p_energy_kwh);
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Log failed: ' || SQLERRM);
END;
/

-- =============================================
-- SECTION 4: FUNCTIONS
-- =============================================

-- Function to calculate maximum daily energy consumption for an appliance
CREATE OR REPLACE FUNCTION appliance_daily_max_kwh (
    p_appliance_id NUMBER
) RETURN NUMBER IS
    result NUMBER;
BEGIN
    SELECT MAX(daily_kwh)
    INTO result
    FROM (
        SELECT SUM(energy_consumed_kwh) AS daily_kwh
        FROM ENERGY_USAGE_RECORD
        WHERE appliance_id = p_appliance_id
        GROUP BY TO_CHAR(timestamp, 'YYYY-MM-DD')
    );
    RETURN result;
EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN 0;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Function error: ' || SQLERRM);
        RETURN -1;
END;
/

-- =============================================
-- SECTION 5: PACKAGES (MODULAR CODE ORGANIZATION)
-- =============================================

-- Main Energy Management Package
CREATE OR REPLACE PACKAGE smart_energy_pkg AS
    PROCEDURE log_energy_record (
        p_record_id NUMBER,
        p_appliance_id NUMBER,
        p_energy_kwh NUMBER
    );
    
    FUNCTION appliance_daily_max_kwh (
        p_appliance_id NUMBER
    ) RETURN NUMBER;
END;
/

CREATE OR REPLACE PACKAGE BODY smart_energy_pkg AS
    PROCEDURE log_energy_record (
        p_record_id NUMBER,
        p_appliance_id NUMBER,
        p_energy_kwh NUMBER
    ) IS
    BEGIN
        INSERT INTO ENERGY_USAGE_RECORD (record_id, appliance_id, timestamp, energy_consumed_kwh)
        VALUES (p_record_id, p_appliance_id, SYSDATE, p_energy_kwh);
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('Insert failed: ' || SQLERRM);
    END;
    
    FUNCTION appliance_daily_max_kwh (
        p_appliance_id NUMBER
    ) RETURN NUMBER IS
        v_max NUMBER;
    BEGIN
        SELECT MAX(daily_kwh)
        INTO v_max
        FROM (
            SELECT SUM(energy_consumed_kwh) AS daily_kwh
            FROM ENERGY_USAGE_RECORD
            WHERE appliance_id = p_appliance_id
            GROUP BY TO_CHAR(timestamp, 'YYYY-MM-DD')
        );
        RETURN v_max;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 0;
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
            RETURN -1;
    END;
END smart_energy_pkg;
/

-- Audit and Security Package
CREATE OR REPLACE PACKAGE energy_audit_pkg AS
    PROCEDURE log_audit_event(
        p_user_id VARCHAR2,
        p_table_name VARCHAR2,
        p_operation VARCHAR2,
        p_record_id NUMBER,
        p_status VARCHAR2,
        p_comments VARCHAR2
    );
    
    FUNCTION is_operation_allowed RETURN BOOLEAN;
END energy_audit_pkg;
/

CREATE OR REPLACE PACKAGE BODY energy_audit_pkg AS
    PROCEDURE log_audit_event(
        p_user_id VARCHAR2,
        p_table_name VARCHAR2,
        p_operation VARCHAR2,
        p_record_id NUMBER,
        p_status VARCHAR2,
        p_comments VARCHAR2
    ) IS
    BEGIN
        INSERT INTO AUDIT_LOG (
            user_id, table_affected, operation_type, 
            record_id, status, comments
        ) VALUES (
            p_user_id, p_table_name, p_operation,
            p_record_id, p_status, p_comments
        );
        COMMIT;
    END log_audit_event;
    
    FUNCTION is_operation_allowed RETURN BOOLEAN IS
        v_day VARCHAR2(3);
        v_holiday_count NUMBER;
    BEGIN
        v_day := TO_CHAR(SYSDATE, 'DY');
        SELECT COUNT(*) INTO v_holiday_count
        FROM HOLIDAYS
        WHERE holiday_date = TRUNC(SYSDATE);
        
        RETURN (v_day NOT IN ('MON', 'TUE', 'WED', 'THU', 'FRI') AND v_holiday_count = 0);
    END is_operation_allowed;
END energy_audit_pkg;
/

-- =============================================
-- SECTION 6: TRIGGERS (BUSINESS RULE ENFORCEMENT)
-- =============================================

-- Trigger to restrict data modifications during weekdays and holidays
CREATE OR REPLACE TRIGGER restrict_weekday_operations
BEFORE INSERT OR UPDATE OR DELETE ON ENERGY_USAGE_RECORD
DECLARE
    v_day_of_week VARCHAR2(3);
    v_is_holiday NUMBER := 0;
    v_error_msg VARCHAR2(100);
BEGIN
    v_day_of_week := TO_CHAR(SYSDATE, 'DY');
    
    BEGIN
        SELECT 1 INTO v_is_holiday
        FROM HOLIDAYS
        WHERE holiday_date = TRUNC(SYSDATE)
        AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_is_holiday := 0;
    END;
    
    IF v_day_of_week IN ('MON', 'TUE', 'WED', 'THU', 'FRI') OR v_is_holiday = 1 THEN
        v_error_msg := CASE 
                          WHEN v_is_holiday = 1 THEN 'Data modifications not allowed on holidays'
                          ELSE 'Data modifications only allowed on weekends (Sat/Sun)'
                       END;
        
        energy_audit_pkg.log_audit_event(
            USER, 'ENERGY_USAGE_RECORD', 
            CASE 
                WHEN INSERTING THEN 'INSERT' 
                WHEN UPDATING THEN 'UPDATE' 
                ELSE 'DELETE' 
            END,
            NULL, 'DENIED', v_error_msg);
        
        RAISE_APPLICATION_ERROR(-20001, v_error_msg);
    END IF;
END;
/

-- =============================================
-- SECTION 7: SAMPLE DATA INSERTION (DML)
-- =============================================

-- Insert sample holidays
INSERT INTO HOLIDAYS VALUES (1, 'Labor Day', TO_DATE('2025-05-01', 'YYYY-MM-DD'), 'International Workers Day');
INSERT INTO HOLIDAYS VALUES (2, 'National Day', TO_DATE('2025-07-01', 'YYYY-MM-DD'), 'Country Independence Day');

-- Insert sample users
INSERT INTO "USER" (user_id, name, email) VALUES (1, 'Test User A', 'usera@example.com');
INSERT INTO "USER" (user_id, name, email) VALUES (2, 'Test User B', 'userb@example.com');

-- Insert sample homes
INSERT INTO HOME (home_id, address, location, user_id) VALUES (101, '123 Green Ave', 'Kigali', 1);
INSERT INTO HOME (home_id, address, location, user_id) VALUES (102, '456 Blue St', 'Musanze', 2);

-- Insert sample appliances
INSERT INTO APPLIANCE (appliance_id, type, brand, status, home_id) VALUES (201, 'Fridge', 'Samsung', 'ON', 101);
INSERT INTO APPLIANCE (appliance_id, type, brand, status, home_id) VALUES (202, 'Washing Machine', 'LG', 'IDLE', 101);
INSERT INTO APPLIANCE (appliance_id, type, brand, status, home_id) VALUES (203, 'Heater', 'Bosch', 'OFF', 102);

-- Insert sample energy usage records
INSERT INTO ENERGY_USAGE_RECORD (record_id, appliance_id, timestamp, energy_consumed_kwh) 
VALUES (301, 201, TO_DATE('2025-05-01 08:00:00', 'YYYY-MM-DD HH24:MI:SS'), 1.50);
INSERT INTO ENERGY_USAGE_RECORD (record_id, appliance_id, timestamp, energy_consumed_kwh) 
VALUES (302, 201, TO_DATE('2025-05-01 12:00:00', 'YYYY-MM-DD HH24:MI:SS'), 1.20);
INSERT INTO ENERGY_USAGE_RECORD (record_id, appliance_id, timestamp, energy_consumed_kwh) 
VALUES (303, 202, TO_DATE('2025-05-01 15:30:00', 'YYYY-MM-DD HH24:MI:SS'), 0.80);

-- =============================================
-- SECTION 8: DATA UPDATES
-- =============================================

-- Update appliance status
UPDATE APPLIANCE SET status = 'ON' WHERE appliance_id = 202;

-- =============================================
-- SECTION 9: ANALYTICAL QUERIES
-- =============================================

-- Calculate total daily usage per appliance using analytic window function
SELECT 
    appliance_id,
    TO_CHAR(timestamp, 'YYYY-MM-DD') AS usage_date,
    SUM(energy_consumed_kwh) OVER (PARTITION BY appliance_id, TO_CHAR(timestamp, 'YYYY-MM-DD')) AS daily_kwh
FROM ENERGY_USAGE_RECORD;

-- =============================================
-- SECTION 10: PL/SQL BLOCKS (BUSINESS LOGIC)
-- =============================================

-- Display maximum daily usage for all appliances
DECLARE
    CURSOR c_appliances IS SELECT appliance_id FROM APPLIANCE;
    v_max NUMBER;
BEGIN
    FOR r IN c_appliances LOOP
        v_max := appliance_daily_max_kwh(r.appliance_id);
        DBMS_OUTPUT.PUT_LINE('Appliance ' || r.appliance_id || ' max daily usage: ' || v_max || ' kWh');
    END LOOP;
END;
/

-- =============================================
-- SECTION 11: TESTING AND VERIFICATION
-- =============================================

-- Test procedure to insert usage
EXEC log_energy_record(400, 201, 2.25);

-- Test function to retrieve max daily usage
SELECT appliance_daily_max_kwh(201) AS max_kwh FROM DUAL;

-- Test weekday restriction verification
SET SERVEROUTPUT ON;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Weekday/Holiday Restriction Test ===');
  DBMS_OUTPUT.PUT_LINE('Current day: ' || TO_CHAR(SYSDATE, 'DAY'));
  
  BEGIN
    INSERT INTO ENERGY_USAGE_RECORD VALUES (999, 201, SYSDATE, 2.5);
    DBMS_OUTPUT.PUT_LINE('TEST FAILED: Operation allowed during restriction period');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('TEST PASSED: ' || SQLERRM);
  END;
END;
/

-- Test audit log verification
SELECT * FROM AUDIT_LOG 
ORDER BY action_date DESC
FETCH FIRST 1 ROW ONLY;

-- Test package function
SELECT CASE 
         WHEN energy_audit_pkg.is_operation_allowed() THEN 'ALLOWED'
         ELSE 'RESTRICTED' 
       END AS operation_status
FROM DUAL;