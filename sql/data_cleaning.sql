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
