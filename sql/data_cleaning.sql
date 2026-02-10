SELECT * FROM customer_support_tickets;

-- creating the copy of the original dataset
CREATE TABLE support_tickets_staging
LIKE customer_support_tickets;

SELECT * FROM support_tickets_staging; -- this created the same columns from the original dataset now copying the complete data

INSERT support_tickets_staging
SELECT *
FROM customer_support_tickets;

SELECT * FROM support_tickets_staging; -- copying completed. Using this to do the analysis

-- Checking for duplicates
SELECT Ticket_ID, Customer_Name, Customer_Email, Submission_Date, COUNT(*) AS duplicate_count
FROM support_tickets_staging
GROUP BY Ticket_ID, Customer_Name, Customer_Email, Submission_Date
HAVING COUNT(*) > 1;
-- No duplicates found

-- checking for NULL/BLANK values
SELECT * FROM support_tickets_staging
WHERE Ticket_ID IS NULL
OR Ticket_ID = '';

SELECT * FROM support_tickets_staging
WHERE Submission_Date IS NULL
OR Submission_Date = '';

SELECT * FROM support_tickets_staging
WHERE Resolution_Time_Hours IS NULL
OR Resolution_Time_Hours = '';

SELECT * FROM support_tickets_staging
WHERE Priority_Level IS NULL
OR Priority_Level = '';

SELECT * FROM support_tickets_staging
WHERE Issue_Category IS NULL
OR Issue_Category = '';

-- No NULL/Blank values found

/* Ticket closure timestamps were not explicitly available, creating "Ticket_Closure_Date" column by calculating 
"Submission_Date" and "Resolution_Time_Hours" to enable time-based SLA analysis */

ALTER TABLE support_tickets_staging
ADD COLUMN Ticket_Closure_Date DATE;

UPDATE support_tickets_staging
SET Ticket_Closure_Date = DATE_ADD(
	Submission_Date,
    INTERVAL Resolution_Time_Hours HOUR
)
WHERE Ticket_ID IS NOT NULL;

SELECT Submission_Date,
Resolution_Time_Hours,
Ticket_Closure_Date
FROM support_tickets_staging
LIMIT 10;

/* Closure date created successfully.
The dataset did not include an explicit ticket closure timestamp. To enable time-based SLA and trend analysis,
a derived Ticket_Closure_Date was calculated by adding the resolution duration (in hours) to the ticket submission date.
As submission timestamps were available only at date level, the closure date was calculated at date granularity.
*/

-- looking for the invalid Resolution_Time_Hours
SELECT * FROM support_tickets_staging
WHERE Resolution_Time_Hours < 0
OR Resolution_Time_Hours = 0; 
-- 	No Invalid Resolution_Time_Hours were found, therefore no remediation was required

-- looking for the higher hours spent on ticket resolution. Currently a standard 72hrs to solve the ticket to be resolved
SELECT COUNT(*)
FROM support_tickets_staging
WHERE Resolution_Time_Hours > 72;
-- Total 3639 tickets which took more than 72 hrs to resolve

SELECT Ticket_ID, Submission_Date, Resolution_Time_hours
FROM support_tickets_staging
ORDER BY Resolution_Time_hours DESC; 
-- MAX hours took to resolve a ticket is 120hrs

SELECT Ticket_ID, Submission_Date, Resolution_Time_hours
FROM support_tickets_staging
ORDER BY Resolution_Time_hours ASC; 
-- MIN hours took to resolve a ticket is 1

SELECT COUNT(*)
FROM support_tickets_staging
WHERE Resolution_Time_Hours = 120;
-- Total 1334 tickets which took 120 hrs to resolve

SELECT * FROM support_tickets_staging;

-- creating 'SLA_Target_Hours' and 'SLA_Status' to define the SLA
ALTER TABLE support_tickets_staging
ADD COLUMN SLA_Target_Hours INT,
ADD COLUMN SLA_Status VARCHAR(20);

/* Adding the SLA Target hours based on the priority level
- Critical = 24hrs
- High = 48hrs
- Medium = 72hrs
- Low = 96hrs */

UPDATE support_tickets_staging
SET SLA_Target_Hours = 
	CASE
		WHEN Priority_Level = 'Critical' THEN 24
        WHEN Priority_Level = 'High' THEN 48
        WHEN Priority_Level = 'Medium' THEN 72
        WHEN Priority_Level = 'Low' THEN 96
	END;
    
-- Based on the Ticket Resolved hrs setting the SLA Status. Is it breached or not
UPDATE support_tickets_staging
SET SLA_Status = 
	CASE
		WHEN Resolution_Time_Hours <= SLA_Target_Hours THEN 'SLA_Met'
        ELSE 'SLA_Breached'
	END;
    
-- Validating the details
SELECT Ticket_ID,
Priority_Level, 
Resolution_Time_Hours,
SLA_Target_Hours,
SLA_Status
FROM support_tickets_staging LIMIT 10;

/* ===============================
   PHASE 2 – MEASURE
   Baseline KPIs
   =============================== */

/* KPI 1 - SLA Compliance %: Measuring the proportion of tickets resolved within their defined SLA targets
the SLA Compliance % is calculated by (Tickets with SLA_Met / Total_Tickets) * 100 */
SELECT
	COUNT(*) AS Total_Tickets,
    SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) AS SLA_Met_Tickets,
    ROUND(
		(SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) / COUNT(*)) * 100,
		2
	) AS SLA_Compliance_Percentage
FROM support_tickets_staging;
/* 
- Total_Tickets: 20000
- SLA_Met_Tickets: 16613
- SLA_Compliance_Percentage: 83.07% 
This indicates that while the majority of tickets meet SLA expectations, ~17% of tickets breach SLA.*/

/* KPI 2 - Avg Resolution Time(MTTR: Mean Time To Resolution)*/

SELECT
	ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_Time_Hours
FROM support_tickets_staging;
-- Overall MTTR = 39.23 hours. means on average a ticket takes ~39hrs to get resolved

SELECT
	Priority_Level,
    ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_Time_Hours
FROM support_tickets_staging
GROUP BY Priority_Level
ORDER BY Avg_Resolution_Time_Hours DESC;

/* Based on the priority level the avg resolution time for tickets
Priority_Level   Avg_Resolution_Time_Hours
Low	             45.17
Medium	         44.47
High	         24.52
Critical	     12.07

The baseline average resolution time across all tickets was 39.23 hours. Resolution time varied significantly by priority level
Critical tickets are resolved fastest (~12 hours) while low and medium priority tickets take almost twice as long*/

/* KPI 3 - SLA Breach by Priority
This is to check which priority levels are most at risk of missing SLAs*/

SELECT
Priority_Level,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS Breached_Tickets,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS Breached_Percentage
FROM support_tickets_staging
GROUP BY Priority_Level
ORDER BY Breached_Percentage DESC;
/* From the output:
Priority_Level     Total_Tickets     Breached_Tickets    Breached_Percentage 
Medium             7570              1703                22.50 
Low                7716              1059                13.72 
High               3416               467                13.67 
Critical           1298               158                12.17 

Total Breached_Tickets count matches with the 3,387 (20,000 − 16,613 SLA met → aligns)
Medium Priority level tickets have the highest  SLA Breach rate*/

/* KPI 4 - Ticket Volume 
In this looking for which priority level the ticket is volume is more*/

SELECT
Priority_Level,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Priority_Level
ORDER BY Total_Tickets DESC;
/* Low and Medium covers 70-75% of ticket volume.
From earlier KPI about SLA breach Medium priority had highest SLA Breach % */

-- Checking for the Ticket Volume based on the Issue Category
SELECT
Issue_Category,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Issue_Category
ORDER BY Total_Tickets DESC; -- Technical and Billing covers 50-55% of all tickets

-- Checking Ticket Volume by Ticket_Channel
SELECT
Ticket_Channel,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Ticket_Channel
ORDER BY Total_Tickets DESC; -- all channels are almost evenly distributed

-- Checking Ticket Volume Over Time like daily, monthly and yearly based total ticket count
SELECT
DATE(Submission_Date) AS Ticket_Created_Date,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Ticket_Created_Date
ORDER BY Total_Tickets DESC;

SELECT
DATE_FORMAT(Submission_Date, '%Y-%m') AS Ticket_Year_Month,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Ticket_Year_Month
ORDER BY Total_Tickets DESC;  -- Monthly ticket volumes are stables with a range of 800 - 860

SELECT
YEAR(Submission_Date) AS Ticket_Created_Year,
COUNT(*) AS Total_Tickets
FROM support_tickets_staging
GROUP BY Ticket_Created_Year
ORDER BY Total_Tickets DESC;

/* KPI 5 - Team-wise Performance 
Cheking for the workload even distribution and SLA breaches is people-related or process-related*/

SELECT
Assigned_Agent,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) AS SLA_Met_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS SLA_Breached_Tickets,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS SLA_Compliance_percent,
ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_Time_Hours
FROM support_tickets_staging
GROUP BY Assigned_Agent
ORDER BY Total_Tickets DESC;

/* KPI 6 - Escalation Rate %
In the dataset there's no column related to escalation count. So using the SLA_Breached tickets as escalated tickets.*/

SELECT
Priority_Level,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS SLA_Breached_Tickets,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS escalation_rate_Percent
FROM support_tickets_staging
GROUP BY Priority_Level
ORDER BY escalation_rate_Percent DESC;

/* =========================================================
   PHASE 3 – ANALYZE
   Root Cause Analysis
   ========================================================= */

/* Analysis 1: Why do Medium priority tickets exhibit the highest SLA breach rate? 

From the earlier "Measure Phase" the medium priority tickets breach rate is 22.50% compared to the other priority level tickets

To answer this analysis by different hypothesis*/

-- 1st hypothesis is to check the total tickets based on priority level, and number of breached tickets from each priority level

SELECT
Priority_Level,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS SLA_Breached_Tickets,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS SLA_Breached_Percent
FROM support_tickets_staging
GROUP BY Priority_Level
ORDER BY SLA_Breached_Percent DESC;
/* Medium-priority tickets have the highest SLA breach rate (22.50%), even higher than High and Critical tickets.
Means Critical & High tickets are actively monitored. To understand about the high breach % checking the based on the Issue_Category
*/

-- checking the breach percent based on the Issue category
SELECT
Priority_Level,
Issue_Category,
COUNT(*) AS Total_Tickets,
ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_hrs,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS Issue_Category_Breached,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) *100, 2) AS Category_Breached_Percent
FROM support_tickets_staging
WHERE Priority_Level = 'Medium'
GROUP BY Issue_Category
ORDER BY Category_Breached_Percent DESC;
-- from the output it shows that all the Issue_Category in the Medium Priority_Level breach at ~22-23% and Avg resolution times are ~43-45hrs

-- Now checking based the ticket channel
SELECT
    Ticket_Channel,
    COUNT(*) AS Total_Medium_Tickets,
    ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_Hours,
    SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS Breached_Tickets,
    ROUND(
        (SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) * 100,
        2
    ) AS Breach_Percentage
FROM support_tickets_staging
WHERE Priority_Level = 'Medium'
GROUP BY Ticket_Channel
ORDER BY Breach_Percentage DESC;

/* Analysis 2: Are certain issue categories disproportionately contributing to SLA breaches?
- any breaches disproportionate relative to ticket volume
- any ticket category inherently risker */

-- checking ticket volume by each category and ticket breach per issue category also the avg resolution time
SELECT
Issue_category,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) AS Category_SLA_Met,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS Category_Breched,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS Category_Breached_Percent,
ROUND(AVG(Resolution_Time_Hours)) AS Avg_Res_hrs
FROM support_tickets_staging
GROUP BY Issue_category
ORDER BY Category_Breached_Percent DESC;


/* Analysis 3: Do ticket channels influence resolution delays?
Checking do ticket channels directly affect*/

-- Checking ticket breach and resolution time by channel
SELECT
Ticket_Channel,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS Ticket_Breached,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) *100, 2) AS Ticket_Breached_Percent,
ROUND(AVG(Resolution_Time_Hours)) AS Ticket_Resolution_Hours
FROM support_tickets_staging
GROUP BY Ticket_Channel
ORDER BY Ticket_Breached_Percent DESC;

SELECT
Ticket_Channel,
Priority_Level,
COUNT(*) AS Total_Tickets,
ROUND(AVG(Resolution_Time_Hours), 2) AS Avg_Resolution_Hours,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) / COUNT(*)) *100, 2) AS Ticket_Breached_Percent
FROM support_tickets_staging
GROUP BY Ticket_Channel, Priority_Level
ORDER BY Ticket_Breached_Percent DESC;

/* Analysis 4: SLA failure caused by underperforming agents, or by systemic process issues?*/
SELECT
Assigned_Agent,
COUNT(*) AS Total_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) AS SLA_Met_Tickets,
SUM(CASE WHEN SLA_Status = 'SLA_Breached' THEN 1 ELSE 0 END) AS SLA_Breached_Tickets,
ROUND((SUM(CASE WHEN SLA_Status = 'SLA_Met' THEN 1 ELSE 0 END) / COUNT(*)) *100, 2) AS SLA_Compliance_Percent,
ROUND(AVG(Resolution_Time_Hours),2) AS Avg_Resolution_Time_Hours
FROM support_tickets_staging
GROUP BY Assigned_Agent
ORDER BY SLA_Compliance_Percent DESC;














