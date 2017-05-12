USE [AdventureWorks2016CTP3]
GO
-- Setup
/*
Author: Steve Howard
Revised: Pedro Lopes
*/
IF EXISTS (SELECT [object_id] FROM sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(N'[Sales].[SalesOrderHeaderBulk]') AND [type] IN (N'U'))
DROP TABLE [Sales].[SalesOrderHeaderBulk];
GO

IF NOT EXISTS (SELECT [object_id] FROM sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(N'[Sales].[SalesOrderHeaderBulk]') AND [type] IN (N'U'))
CREATE TABLE [Sales].[SalesOrderHeaderBulk](
	[SalesOrderID] [INT] IDENTITY(1,1) NOT FOR REPLICATION NOT NULL,
	[RevisionNumber] [tinyint] NOT NULL,
	[OrderDate] [datetime] NOT NULL,
	[DueDate] [datetime] NOT NULL,
	[ShipDate] [datetime] NULL,
	[Status] [tinyint] NOT NULL,
	[CustomerID] [INT] NOT NULL,
	[ContactID] [INT] NULL,
	[SalesPersonID] [INT] NULL,
	[TerritoryID] [INT] NULL,
	[BillToAddressID] [INT] NOT NULL,
	[ShipToAddressID] [INT] NOT NULL,
	[ShipMethodID] [INT] NOT NULL,
	[CreditCardID] [INT] NULL,
	[CreditCardApprovalCode] [varchar](15) NULL,
	[CurrencyRateID] [INT] NULL,
	[SubTotal] [money] NOT NULL,
	[TaxAmt] [money] NOT NULL,
	[Freight] [money] NOT NULL,
	[TotalDue] AS (ISNULL(([SubTotal]+[TaxAmt])+[Freight],(0))),
	[Comment] [nvarchar](128) NULL,
	[ModifiedDate] [datetime] NOT NULL,
	CONSTRAINT [PK_SalesOrderHeaderBulk_SalesOrderID] PRIMARY KEY CLUSTERED 
		(
			[SalesOrderID] ASC
		)
)
GO

IF EXISTS (SELECT [object_id] FROM sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(N'[Sales].[SalesOrderDetailBulk]') AND [type] IN (N'U'))
DROP TABLE [Sales].[SalesOrderDetailBulk];
GO

IF NOT EXISTS (SELECT [object_id] FROM sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID(N'[Sales].[SalesOrderDetailBulk]') AND [type] IN (N'U'))
CREATE TABLE [Sales].[SalesOrderDetailBulk](
	[SalesOrderID] [INT] NOT NULL,
	[SalesOrderDetailBulkID] [INT] IDENTITY(1,1) NOT NULL,
	[CarrierTrackingNumber] [nvarchar](25) NULL,
	[OrderQty] [smallint] NOT NULL,
	[ProductID] [INT] NOT NULL,
	[SpecialOfferID] [INT] NOT NULL,
	[UnitPrice] [money] NOT NULL,
	[UnitPriceDiscount] [money] NOT NULL,
	[LineTotal]  AS (isnull(([UnitPrice]*((1.0)-[UnitPriceDiscount]))*[OrderQty],(0.0))),
	[rowguid] [uniqueidentifier] ROWGUIDCOL  NOT NULL,
	[ModifiedDate] [datetime] NOT NULL,
	CONSTRAINT [PK_SalesOrderDetailBulk_SalesOrderID_SalesOrderDetailBulkID] PRIMARY KEY CLUSTERED 
		(
			[SalesOrderID] ASC,
			[SalesOrderDetailBulkID] ASC
		)
)
GO

-- Populate Tables
DECLARE @i smallint
SET @i = 0
WHILE @i < 50
BEGIN
	INSERT INTO Sales.SalesOrderHeaderBulk (RevisionNumber, OrderDate, DueDate, ShipDate, Status, CustomerID, ContactID, SalesPersonID, TerritoryID, BillToAddressID, 
	ShipToAddressID, ShipMethodID, CreditCardID, CreditCardApprovalCode, CurrencyRateID, SubTotal, TaxAmt, Freight, Comment, ModifiedDate)
	SELECT RevisionNumber, OrderDate, DueDate, ShipDate, Status, CustomerID, NULL, SalesPersonID, TerritoryID, BillToAddressID, 
		ShipToAddressID, ShipMethodID, CreditCardID, CreditCardApprovalCode, CurrencyRateID, SubTotal, TaxAmt, Freight, Comment, ModifiedDate
	FROM Sales.SalesOrderHeader;

	INSERT INTO Sales.SalesOrderDetailBulk (SalesOrderID, CarrierTrackingNumber, OrderQty, ProductID, SpecialOfferID, UnitPrice, UnitPriceDiscount, rowguid, ModifiedDate)
	SELECT SalesOrderID, CarrierTrackingNumber, OrderQty, ProductID, SpecialOfferID, UnitPrice, UnitPriceDiscount, rowguid, ModifiedDate
	FROM Sales.SalesOrderDetail;
	
	SET @i = @i +1
END
GO

-- Create index
CREATE NONCLUSTERED INDEX [IX_ModifiedDate_OrderQty] ON [Sales].[SalesOrderDetailBulk] ([ModifiedDate] ASC)
INCLUDE ([ProductID],[OrderQty]) 
GO

-- Demo - The benefits of predicate pushdown vs other approaches
DBCC FREEPROCCACHE
GO
DBCC DROPCLEANBUFFERS
GO
-- Disallow non-sarg expressions to be pushed to storage engine
SELECT [ProductID]
FROM [Sales].[SalesOrderDetail]
WHERE [ModifiedDate] BETWEEN '2011-01-01' AND '2012-01-01'
AND [OrderQty] = 2
OPTION (QUERYTRACEON 9130)
GO
DBCC DROPCLEANBUFFERS
GO
-- non-sarg expressions are pushed to storage engine
SELECT [ProductID]
FROM [Sales].[SalesOrderDetail]
WHERE [ModifiedDate] BETWEEN '2011-01-01' AND '2012-01-01'
AND [OrderQty] = 2
GO

-- Look Range Scan predicate ranges
-- Look at CPU and elapsed time diffs

-- Drop new index
DROP INDEX [Sales].[SalesOrderDetailBulk].[IX_ModifiedDate_OrderQty] 
GO

-- Demo - Predicate pushdown unleashed
DBCC FREEPROCCACHE
DBCC DROPCLEANBUFFERS
GO
--Query 1
SELECT FirstName, LastName 
FROM Person.Person
WHERE LastName like 'S%'
AND FirstName = 'John'; 
GO
DBCC DROPCLEANBUFFERS
GO
--Query 2
SELECT FirstName, LastName 
FROM Person.Person 
WHERE LastName = 'Smith' 
AND FirstName like 'J%';
GO


-- Look Range Scan predicate ranges
-- Look at IO differences




-- Part 2 (optional)

-- Let's analyze specifically query 2 and where the estimation is coming from

--Query 2

-- Estimation coming from index stats?
SELECT SUM(hist.range_rows + hist.equal_rows) AS all_rows
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_histogram(s.[object_id], s.stats_id) AS hist
WHERE s.[name] = N'IX_Person_LastName_FirstName_MiddleName'
AND CAST(range_high_key AS varchar) = 'Smith';
GO

-- Not quite, let's use the header info and density_vector instead.
SELECT prop.*
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.[object_id], s.stats_id) AS prop
WHERE s.[name] = N'IX_Person_LastName_FirstName_MiddleName';
GO
DBCC SHOW_STATISTICS('Person.Person','IX_Person_LastName_FirstName_MiddleName') WITH DENSITY_VECTOR;
GO

/* Cant use above? Calculate like this
DECLARE @tbl TABLE (AllDensity float, AverageLenght float, [Columns] varchar(128))
INSERT INTO @tbl
EXEC ('dbcc show_statistics(''Person.Person'',''IX_Person_LastName_FirstName_MiddleName'') WITH DENSITY_VECTOR')
SELECT STR(AllDensity,18,17) AS AllDensity, AverageLenght, [Columns] from @tbl
GO
*/

-- Density for both predicates
SELECT 19972 * 0.0000512400074513;
GO



-- Ok, so from where?
DROP EVENT SESSION [XeNewCE] ON SERVER 
GO
CREATE EVENT SESSION [XeNewCE] ON SERVER 
ADD EVENT sqlserver.query_optimizer_estimate_cardinality(
    ACTION(sqlserver.sql_text)),
ADD EVENT sqlserver.query_optimizer_force_both_cardinality_estimation_behaviors 
ADD TARGET package0.event_file(SET filename=N'C:\IP\Tiger\Gems to help you troubleshoot query performance\Demos\Demo 4 - Predicate Pushdown\XeNewCE.xel',max_file_size=(50),max_rollover_files=(2))
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

ALTER EVENT SESSION [XeNewCE] ON SERVER STATE = START
GO
SELECT FirstName, LastName 
FROM Person.Person 
WHERE LastName = 'Smith' 
AND FirstName like 'J%';
GO
ALTER EVENT SESSION [XeNewCE] ON SERVER STATE = STOP
GO

--ExponentialBackoff
SELECT 0.005*SQRT(0.118)*19972