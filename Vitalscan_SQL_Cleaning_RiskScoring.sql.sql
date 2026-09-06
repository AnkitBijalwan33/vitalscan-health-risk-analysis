                 -- VitalScan: Smoking Health Risk Analysis
-- SQL Workflow: Setup -> Cleaning Checks -> Column Selection -> Business Queries -> Risk Score

CREATE DATABASE IF NOT EXISTS vitalscan_db;
USE vitalscan_db;


DROP TABLE IF EXISTS health_dataset;
 
CREATE TABLE health_dataset (
    Patient_ID           INT PRIMARY KEY,
    Age                  INT,
    Gender               VARCHAR(10),
    Smoking_Status       VARCHAR(15),
    Years_of_Smoking     INT,
    Cigarettes_Per_Day   INT,
    Organ                VARCHAR(20),
    Organ_Condition      VARCHAR(10),
    BMI                  DECIMAL(4,1),
    BP_Risk              VARCHAR(10),
    Cholesterol_Level     DECIMAL(5,1),
    Family_History_Risk  VARCHAR(5),
    Alcohol_Consumption  VARCHAR(10)
);

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE "health_dataset.csv"
INTO TABLE health_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Patient_ID, Age, Gender, Smoking_Status, Years_of_Smoking, Cigarettes_Per_Day, Organ, Organ_Condition, BMI, BP_Risk, Cholesterol_Level, Family_History_Risk, Alcohol_Consumption, @dummy1, @dummy2);

-- ===== cleaning checks =====
 
SELECT COUNT(*) AS Total_Rows FROM health_dataset;  -- should be 2500
 
SELECT Patient_ID, COUNT(*) AS Record_Count         -- duplicate check
FROM health_dataset
GROUP BY Patient_ID
HAVING COUNT(*) > 1;
 
SELECT                                              -- null check
    SUM(Age IS NULL) AS Null_Age,
    SUM(Gender IS NULL) AS Null_Gender,
    SUM(Smoking_Status IS NULL) AS Null_Smoking_Status,
    SUM(BMI IS NULL) AS Null_BMI,
    SUM(BP_Risk IS NULL) AS Null_BP_Risk,
    SUM(Cholesterol_Level IS NULL) AS Null_Cholesterol,
    SUM(Family_History_Risk IS NULL) AS Null_Family_History,
    SUM(Alcohol_Consumption IS NULL) AS Null_Alcohol
FROM health_dataset;
 
SELECT MIN(Age) Min_Age, MAX(Age) Max_Age,          -- range check
       MIN(BMI) Min_BMI, MAX(BMI) Max_BMI,
       MIN(Cholesterol_Level) Min_Chol, MAX(Cholesterol_Level) Max_Chol
FROM health_dataset;
 
SELECT DISTINCT Gender FROM health_dataset;         -- category checks
SELECT DISTINCT Smoking_Status FROM health_dataset;
SELECT DISTINCT BP_Risk FROM health_dataset;
SELECT DISTINCT Alcohol_Consumption FROM health_dataset;
SELECT DISTINCT Family_History_Risk FROM health_dataset;
SELECT DISTINCT Organ_Condition FROM health_dataset;
 
-- all checks came back clean, no rows dropped
 
 
-- ===== working view (rebuilds Age Group in SQL) =====
 
CREATE OR REPLACE VIEW vw_health_working AS
SELECT
    Patient_ID, Age,
    CASE
        WHEN Age <= 28 THEN '18-28'
        WHEN Age <= 38 THEN '29-38'
        WHEN Age <= 48 THEN '39-48'
        WHEN Age <= 58 THEN '49-58'
        WHEN Age <= 68 THEN '59-68'
        ELSE '69+'
    END AS Age_Group,
    Gender, Smoking_Status, Years_of_Smoking, Cigarettes_Per_Day,
    Organ, Organ_Condition, BMI, BP_Risk, Cholesterol_Level,
    Family_History_Risk, Alcohol_Consumption
FROM health_dataset;
 
 
-- ===== business questions =====
 
-- Q1: total patients
SELECT COUNT(*) AS Total_Patients FROM health_dataset;
 
-- Q2: smoker split
SELECT Smoking_Status, COUNT(*) AS Patient_Count,
       ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM health_dataset),1) AS Pct
FROM health_dataset
GROUP BY Smoking_Status
ORDER BY Patient_Count DESC;
 
-- Q3: smoking by gender
SELECT Gender, Smoking_Status, COUNT(*) AS Patient_Count
FROM health_dataset
GROUP BY Gender, Smoking_Status
ORDER BY Gender, Patient_Count DESC;
 
-- Q4: avg cholesterol by age group
SELECT Age_Group, ROUND(AVG(Cholesterol_Level),1) AS Avg_Cholesterol
FROM vw_health_working
GROUP BY Age_Group
ORDER BY Age_Group;
 
-- Q5: BP risk by age group
SELECT Age_Group, BP_Risk, COUNT(*) AS Patient_Count
FROM vw_health_working
GROUP BY Age_Group, BP_Risk
ORDER BY Age_Group, BP_Risk;
 
-- Q6: smoking duration vs daily intake, by age group
SELECT Age_Group,
       ROUND(AVG(Years_of_Smoking),1) AS Avg_Years_Smoking,
       ROUND(AVG(Cigarettes_Per_Day),1) AS Avg_Cigs_Per_Day
FROM vw_health_working
WHERE Smoking_Status IN ('Current','Former')
GROUP BY Age_Group
ORDER BY Age_Group;
 
-- Q7: alcohol consumption split
SELECT Alcohol_Consumption, COUNT(*) AS Patient_Count,
       ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM health_dataset),1) AS Pct
FROM health_dataset
GROUP BY Alcohol_Consumption
ORDER BY Patient_Count DESC;
 
-- Q8: avg age and BMI
SELECT ROUND(AVG(Age),1) AS Avg_Age, ROUND(AVG(BMI),1) AS Avg_BMI
FROM health_dataset;
 
-- Q9: damaged rate by organ
SELECT Organ, Organ_Condition, COUNT(*) AS Patient_Count,
       ROUND(COUNT(*)*100.0/SUM(COUNT(*)) OVER (PARTITION BY Organ),1) AS Pct_Within_Organ
FROM health_dataset
GROUP BY Organ, Organ_Condition
ORDER BY Organ, Organ_Condition;
 
 
-- ===== risk score =====
-- points: smoking + BP risk + cholesterol + family history + alcohol
 
CREATE OR REPLACE VIEW vw_risk_score AS
SELECT *,
    (CASE WHEN Smoking_Status='Current' THEN 3 WHEN Smoking_Status='Former' THEN 1 ELSE 0 END +
     CASE WHEN BP_Risk='High' THEN 3 WHEN BP_Risk='Normal' THEN 1 ELSE 0 END +
     CASE WHEN Cholesterol_Level>=240 THEN 2 WHEN Cholesterol_Level>=200 THEN 1 ELSE 0 END +
     CASE WHEN Family_History_Risk='Yes' THEN 2 ELSE 0 END +
     CASE WHEN Alcohol_Consumption='High' THEN 2 WHEN Alcohol_Consumption='Moderate' THEN 1 ELSE 0 END
    ) AS Risk_Score
FROM health_dataset;
 
-- tier + how many patients in each
SELECT
    CASE WHEN Risk_Score>=8 THEN 'High' WHEN Risk_Score>=4 THEN 'Medium' ELSE 'Low' END AS Risk_Tier,
    COUNT(*) AS Patient_Count,
    ROUND(AVG(Cholesterol_Level),1) AS Avg_Cholesterol,
    ROUND(SUM(Smoking_Status='Current')*100.0/COUNT(*),1) AS Pct_Current_Smokers
FROM vw_risk_score
GROUP BY
    CASE WHEN Risk_Score>=8 THEN 'High' WHEN Risk_Score>=4 THEN 'Medium' ELSE 'Low' END;
 
-- Insight: High Risk tier is ~74% current smokers, ~54% high BP, ~63% family
-- history, vs ~2%, ~4%, ~8% in Low Risk. Score clearly separates patients.
-- Organ_Condition doesn't correlate with these factors in this dataset, so
-- the score is used as a screening-priority tool, not an outcome predictor.
 
-- Recommendation: call High Risk patients in for cardiac/lung screening first.