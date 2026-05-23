RESTORE FILELISTONLY
FROM DISK = 'E:\azure-data-engineering\sql\AdventureWorks2019.bak';


RESTORE DATABASE AdventureWorksLT2019
FROM DISK = 'E:\azure-data-engineering\sql\AdventureWorks2019.bak'
WITH MOVE 'AdventureWorks2019' TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\AdventureWorksLT2019.mdf',
     MOVE 'AdventureWorks2019_log'  TO 'C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\AdventureWorksLT2019.ldf',
     REPLACE;
