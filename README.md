# Azure End-to-End Data Engineering Real-Time Project

## Project Overview

This project addresses a critical business need by building a comprehensive data pipeline on Azure. The goal is to extract customer and sales data from an on-premises SQL database, transform it in the cloud, and generate actionable insights through a Power BI dashboard. The dashboard will highlight key performance indicators (KPIs) related to gender distribution and product category sales, allowing stakeholders to filter and analyze data by date, product category, and gender.

## Architecture

```
On-Premises SQL Server (AdventureWorksLT2019)
        │
        │  Azure Data Factory (Self-hosted Integration Runtime)
        ▼
ADLS Gen2 – Bronze Layer (raw Parquet)
        │
        │  Azure Databricks (datetime cleanup)
        ▼
ADLS Gen2 – Silver Layer (cleansed Delta)
        │
        │  Azure Databricks (column rename: PascalCase → UPPER_SNAKE_CASE)
        ▼
ADLS Gen2 – Gold Layer (analytics-ready Delta)
        │
        │  Azure Synapse Analytics (serverless SQL views)
        ▼
Power BI Dashboard (gender split, revenue, product KPIs)
```

## Business Requirements

The business has identified a gap in understanding customer demographics—specifically gender distribution—and how it influences product purchases. The key requirements include:

1. **Sales by Gender and Product Category**: A dashboard showing the total products sold, total sales revenue, and a gender split among customers.
2. **Data Filtering**: Ability to filter the data by product category, gender, and date.
3. **User-Friendly Interface**: Stakeholders should have access to an easy-to-use interface for making queries.

## Solution Overview

To meet these requirements, the solution is broken down into the following components:

1. **Data Ingestion**:
    - Extract customer and sales data from an on-premises SQL database.
    - Load the data into Azure Data Lake Storage (ADLS) using Azure Data Factory (ADF).
    - A **Self-hosted Integration Runtime** is installed on the on-premises machine to bridge the on-prem SQL Server and the ADF cloud service.

2. **Data Transformation**:
    - Use Azure Databricks to clean and transform the data.
    - Organize the data into Bronze, Silver, and Gold layers for raw, cleansed, and aggregated data respectively.

3. **Data Loading and Reporting**:
    - Load the transformed data into Azure Synapse Analytics.
    - Build a Power BI dashboard to visualize the data, allowing stakeholders to explore sales and demographic insights.

4. **Automation**:
    - Schedule the pipeline to run daily, ensuring that the data and reports are always up-to-date.

## Technology Stack

- **Azure Data Factory (ADF)**: For orchestrating data movement and transformation, including a Self-hosted Integration Runtime for on-premises connectivity.
- **Azure Data Lake Storage Gen2 (ADLS)**: For storing raw and processed data across Bronze, Silver, and Gold layers.
- **Azure Databricks**: For data transformation and processing using Delta Lake format.
- **Azure Synapse Analytics**: For data warehousing and serverless SQL-based analytics.
- **Power BI Desktop** *(Windows only)*: For data visualization and reporting.
- **Azure Key Vault**: For securely managing credentials and secrets.
- **Azure Entra ID** *(formerly Active Directory)*: For identity management and role-based access control (RBAC).
- **SQL Server Express + SSMS (On-Premises)**: Source of customer and sales data (AdventureWorksLT2019).

## Setup Instructions

### Prerequisites

- An Azure account with sufficient credits (new accounts get $200 free for 30 days).
- A Windows machine for the Self-hosted Integration Runtime and Power BI Desktop.
- SQL Server Express installed locally ([download here](https://www.microsoft.com/en-us/sql-server/sql-server-downloads)).
- SQL Server Management Studio (SSMS) installed ([download here](https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms)).
- **AdventureWorksLT2019** sample database restored to your local SQL Server (see Step 0 below).

---

### Step 0: Restore AdventureWorksLT2019 (On-Premises Database)

1. Download `AdventureWorksLT2019.bak` from the [Microsoft SQL Server Samples releases](https://github.com/Microsoft/sql-server-samples/releases/tag/adventureworks).
2. Copy the `.bak` file to your SQL Server backup directory, e.g.:
   ```
   C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\Backup\
   ```
3. In SSMS, right-click **Databases** → **Restore Database…** → **Device** → browse to the `.bak` file, or run:
   ```sql
   RESTORE DATABASE AdventureWorksLT2019
   FROM DISK = 'C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\Backup\AdventureWorksLT2019.bak'
   WITH MOVE 'AdventureWorksLT2019_Data' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\AdventureWorksLT2019.mdf',
        MOVE 'AdventureWorksLT2019_Log'  TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\AdventureWorksLT2019.ldf',
        REPLACE;
   ```
4. In SSMS, right-click the server → **Properties** → **Security** → set Server Authentication to **SQL Server and Windows Authentication mode**. Restart the SQL Server service via SQL Server Configuration Manager.
5. Create a dedicated SQL login and grant it access to the SalesLT schema:
   ```sql
   USE AdventureWorksLT2019;
   GRANT SELECT ON SCHEMA::SalesLT TO <your_login>;
   ```
6. Store the login credentials as secrets in Azure Key Vault (used by ADF linked service).

---

### Step 1: Azure Environment Setup

1. **Create Resource Group**: Set up a new resource group in Azure.
2. **Provision Services**:
   - Create an **Azure Data Factory** instance.
   - Set up **Azure Data Lake Storage Gen2** with `bronze`, `silver`, and `gold` containers.
   - Set up an **Azure Databricks** workspace and **Synapse Analytics** workspace.
   - Configure **Azure Key Vault** for secret management.

### Step 2: Data Ingestion

1. **Install Self-hosted Integration Runtime**: In ADF Studio → Manage → Integration Runtimes → New → Self-hosted. Install the runtime on your local machine (the same machine running SQL Server) so ADF can reach the on-premises database.
2. **Ingest Data with ADF**: Create a pipeline using a Lookup + ForEach pattern to dynamically copy all tables under the `SalesLT` schema from SQL Server to the `bronze` layer in ADLS as Parquet files, structured as `bronze/SalesLT/<TableName>/<TableName>.parquet`.

### Step 3: Data Transformation

1. **Mount Data Lake in Databricks**: Configure Databricks to access ADLS using credential passthrough, mounting the `bronze`, `silver`, and `gold` containers.
2. **Bronze → Silver**: Use a Databricks notebook to convert all `datetime` columns to `date` type and write output in Delta format to the `silver` container.
3. **Silver → Gold**: Use a Databricks notebook to rename columns from `PascalCase` to `UPPER_SNAKE_CASE` and write output in Delta format to the `gold` container.
4. **Orchestrate via ADF**: Add Databricks notebook activities to the ADF pipeline (triggered after the ForEach copy step completes).

### Step 4: Data Loading and Reporting

1. **Load Data into Synapse**: Create a serverless SQL pool database (`gold_db`) in Synapse. Use a dynamic stored procedure + pipeline to create SQL views over the Gold Delta Lake files.
2. **Create Power BI Dashboard**: Connect Power BI Desktop to the Synapse serverless SQL endpoint. Build visualizations:
   - Card: Total products sold
   - Card: Total sales revenue
   - Donut chart: Gender split (inferred from customer title)
   - Slicers: Filter by product category and gender
   > ⚠️ **Power BI Desktop requires Windows.** If you're on macOS/Linux, you can use the Power BI web experience within Synapse as an alternative.

### Step 5: Automation and Monitoring

1. **Schedule Pipelines**: Use ADF to schedule the data pipelines to run daily at a specified time.
2. **Monitor Pipeline Runs**: Use the monitoring tools in ADF and Synapse to ensure successful pipeline execution.

### Step 6: Security and Governance

1. **Manage Access with Entra ID**: Create security groups in Azure Entra ID (formerly Active Directory) to manage team-level access. Assign groups to resource-level RBAC roles rather than granting access to individual users, making onboarding and offboarding easier.

### Step 7: End-to-End Testing

1. **Trigger and Test Pipelines**: Insert new records into the SQL database (e.g., a new row in `SalesLT.Product`) and verify that the entire pipeline runs successfully, updating the Power BI dashboard automatically on the next scheduled trigger.

## Conclusion

This project provides a robust end-to-end solution for understanding customer demographics and their impact on sales. The automated data pipeline ensures that stakeholders always have access to the most current and actionable insights.
