# Preprocess datasets
#Step1 check table
SELECT * FROM Checks;
SELECT * FROM Designer;
SELECT * FROM DesignerCheck;
SELECT * FROM Project;
SELECT * FROM ProjectCustomer;
SELECT * FROM ProjectDesigner;
SELECT * FROM ProjectTask;
SELECT * FROM Timesheet;
SELECT * FROM Vendor;
SELECT * FROM VendorCheck;

#Step2 Define PK and FK
ALTER TABLE Project ADD CONSTRAINT pk_p PRIMARY KEY (ProjectID);
ALTER TABLE ProjectCustomer ADD CONSTRAINT pk_pc PRIMARY KEY (ProjectID, Customer(100)),
ADD CONSTRAINT fk_pcp FOREIGN KEY (ProjectID) REFERENCES Project(ProjectID);
ALTER TABLE ProjectTask ADD CONSTRAINT pk_pt PRIMARY KEY (ProjectID, TaskDescription(500)),
ADD CONSTRAINT fk_ptp FOREIGN KEY (ProjectID) REFERENCES Project(ProjectID);
ALTER TABLE Designer ADD CONSTRAINT pk_d PRIMARY KEY (DesignerID);
ALTER TABLE ProjectDesigner ADD CONSTRAINT pk_pd PRIMARY KEY (ProjectID, DesignerID),
ADD CONSTRAINT fk_pdp FOREIGN KEY (ProjectID) REFERENCES Project(ProjectID),
ADD CONSTRAINT fk_pdd FOREIGN KEY (DesignerID) REFERENCES Designer(DesignerID);
ALTER TABLE Checks ADD CONSTRAINT pk_c PRIMARY KEY (CheckID);
ALTER TABLE Timesheet ADD CONSTRAINT pk_t PRIMARY KEY (DesignerID, ProjectID, WorkDate(100), TimeStarted(100));
SET SQL_SAFE_UPDATES = 0;
UPDATE Timesheet SET CheckID=NULL WHERE CheckID=0;
SET SQL_SAFE_UPDATES = 1;
ALTER TABLE Timesheet ADD CONSTRAINT fk_tp FOREIGN KEY (ProjectID) REFERENCES Project(ProjectID);
ALTER TABLE Timesheet ADD CONSTRAINT fk_td FOREIGN KEY (DesignerID) REFERENCES Designer(DesignerID);
ALTER TABLE Timesheet ADD CONSTRAINT fk_tc FOREIGN KEY (CheckID) REFERENCES Checks(CheckID);
ALTER TABLE Vendor ADD CONSTRAINT pk_v PRIMARY KEY (VendorID);
ALTER TABLE VendorCheck ADD CONSTRAINT pk_vc PRIMARY KEY (CheckID),
ADD CONSTRAINT fk_vcv FOREIGN KEY (VendorID) REFERENCES Vendor(VendorID);
ALTER TABLE VendorCheck ADD CONSTRAINT fk_vcc FOREIGN KEY (CheckID) REFERENCES Checks(CheckID);
ALTER TABLE DesignerCheck ADD CONSTRAINT pk_dc PRIMARY KEY (CheckID),
ADD CONSTRAINT fk_dcd FOREIGN KEY (DesignerID) REFERENCES Designer(DesignerID);
ALTER TABLE DesignerCheck ADD CONSTRAINT fk_dcc FOREIGN KEY (CheckID) REFERENCES Checks(CheckID);

# Step3 change datatype
ALTER TABLE Timesheet MODIFY WorkDate date, MODIFY TimeStarted time, MODIFY TimeEnded time;


# Query 1
# Calculate designers’ task duration, total wage per record of timesheet
SELECT Timesheet.DesignerID, Designer.DesignerFN, Designer.DesignerLN, ProjectID, WorkDate, TIME_TO_SEC(timediff(TimeEnded, TimeStarted))/3600 AS DurationHr, 
Designer.HourlyWage, @wage := ROUND(TIME_TO_SEC(timediff(TimeEnded, TimeStarted))/3600*HourlyWage, 2) AS Wage
FROM Timesheet LEFT JOIN Designer ON Timesheet.DesignerID = Designer.DesignerID
ORDER BY WorkDate;


# Query 2
# Which employee has the most total payment in each role per month?
SELECT *
FROM(SELECT Year(Timesheet.WorkDate) AS Year, Month(Timesheet.WorkDate) AS Month, Designer.Role,
Designer.DesignerID, Designer.DesignerFN, Designer.DesignerLN, SUM(ROUND(TIME_TO_SEC(timediff(TimeEnded, TimeStarted))/3600*HourlyWage, 2)) AS TotalWage
FROM Timesheet INNER JOIN Designer ON Timesheet.DesignerID = Designer.DesignerID
GROUP BY Year, Month, Designer.DesignerID) AS T
WHERE TotalWage = (SELECT MAX(TotalWage) FROM Timesheet INNER JOIN Designer ON Timesheet.DesignerID = Designer.DesignerID)
GROUP BY Year, Month, Role;


# Query 3
# List all the records and the expected payment amount in the timesheet which are not paid at designer level per month
SELECT Year(Timesheet.WorkDate) AS Year, Month(Timesheet.WorkDate) AS Month, Designer.DesignerID, SUM(ROUND(TIME_TO_SEC(timediff(TimeEnded, TimeStarted))/3600*HourlyWage, 2)) AS TotalWage
FROM Timesheet INNER JOIN Designer ON Timesheet.DesignerID = Designer.DesignerID
WHERE CheckID IS NULL
GROUP BY Month, DesignerID 
ORDER BY Month, DesignerID;


# Query 4
# Which companies are Design Alternatives' top vendors
SELECT  Vendor.VendorName, sum(PurchaseAmount) AS TotalAmount,  count(VendorCheck.VendorID) AS Frequency FROM VendorCheck
LEFT JOIN Vendor ON Vendor.VendorID = VendorCheck.VendorID
GROUP BY VendorCheck.VendorID
HAVING TotalAmount >  500 or Frequency > 1
ORDER BY Frequency DESC, TotalAmount DESC; 


# Query 5 
# Make payments to designers: eg. Newcheck id is 5547; date is December 2nd, 2021; designer id is 2; payroll period is October, 2021.
# Step 1: write a check to the designer
INSERT INTO Checks VALUES (@newcheck := 5547, '2021/12/02', 'Outstanding');
INSERT INTO DesignerCheck VALUES (
	@newcheck, @payee :=2, (
		SELECT SUM(ROUND(TIME_TO_SEC(timediff(TimeEnded, TimeStarted))/3600*HourlyWage, 2))
        FROM Timesheet INNER JOIN Designer ON Timesheet.DesignerID = Designer.DesignerID
        WHERE Year(Timesheet.WorkDate) = 2021 AND Month(Timesheet.WorkDate) = 10 AND Designer.DesignerID = @payee AND CheckID IS NULL));
        
UPDATE Timesheet SET CheckID = @newcheck
WHERE Year(WorkDate) = 2021 AND Month(WorkDate) = 10 AND DesignerID = @payee AND CheckID IS NULL;

# Step 2: the check is cashed
UPDATE Checks SET Status = 'Cashed' WHERE CheckID = @newcheck;


# Query 6
# List the top 5 loyal customers through the frequency of projects
SELECT ProjectCustomer.Customer, COUNT(Timesheet.ProjectID) AS FrequencyofCustomer FROM ProjectCustomer
INNER JOIN Timesheet ON Timesheet.ProjectID = ProjectCustomer.ProjectID
GROUP BY ProjectCustomer.Customer ORDER BY FrequencyofCustomer DESC LIMIT 5;


# Query 7
# The time spent and the cost group by designers of project No.375 (project customer information included)
SELECT Timesheet.DesignerID, Designer.HourlyWage, sum(TIME_TO_SEC(timediff(Timesheet.TimeEnded, Timesheet.TimeStarted))/3600) AS DurationHr, HourlyWage*sum(TIME_TO_SEC(timediff(Timesheet.TimeEnded, Timesheet.TimeStarted))/3600) AS LaborCost FROM Timesheet
INNER JOIN Designer ON Designer.DesignerID = Timesheet.DesignerID
WHERE ProjectID = 375
GROUP BY Timesheet.DesignerID;


# Query 8
# The ratio of local projects for Design Alternatives
SELECT 
count(CASE WHEN ProjectAddress LIKE "%Lafayette%" then 1 else null end)/count(*) AS LocalProjectRatio
FROM Project;


# Query 9
# Which project has the longest duration and how many designers work for this project?
SELECT ProjectID, (Max(WorkDate) - min(WorkDate) + 1) AS ProjectDays, count(DesignerID) AS NumberofDesigner FROM Timesheet
GROUP BY ProjectID
ORDER BY ProjectDays DESC,count(DesignerID) DESC;


# Query 10
# What amount of money from the check hasn't been cashed?
SELECT (COALESCE(SUM(PurchaseAmount),0)+ COALESCE(SUM(PayrollAmount),0)) AS TotalOutstanding FROM Checks
LEFT JOIN VendorCheck on VendorCheck.CheckID = Checks.CheckID
LEFT JOIN DesignerCheck on DesignerCheck.CheckID = Checks.CheckID
WHERE Status = "Outstanding";


