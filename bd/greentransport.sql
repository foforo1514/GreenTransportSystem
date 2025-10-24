

IF DB_ID(N'GreenTransportDB') IS NOT NULL
BEGIN
    ALTER DATABASE GreenTransportDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GreenTransportDB;
END
GO

-- 2) Crear DB y usarla
CREATE DATABASE GreenTransportDB;
GO
USE GreenTransportDB;
GO

-- 3) Esquema dedicado
CREATE SCHEMA gt AUTHORIZATION dbo;
GO

-- 4) Tablas
CREATE TABLE gt.Vehiculos (
    VehiculoID   INT IDENTITY(1,1) PRIMARY KEY,
    Placa        VARCHAR(15) NOT NULL UNIQUE,
    Modelo       VARCHAR(100) NOT NULL,
    Activo       BIT NOT NULL DEFAULT (1),
    Disponible   BIT NOT NULL DEFAULT (1),   -- disponibilidad operativa actual
    FechaAlta    DATE NOT NULL DEFAULT (CONVERT(date, GETDATE()))
);

CREATE TABLE gt.Conductores (
    ConductorID  INT IDENTITY(1,1) PRIMARY KEY,
    Nombre       NVARCHAR(120) NOT NULL,
    Licencia     VARCHAR(30) NOT NULL UNIQUE,
    Activo       BIT NOT NULL DEFAULT (1)
);

CREATE TABLE gt.Mantenimientos (
    MantenimientoID INT IDENTITY(1,1) PRIMARY KEY,
    VehiculoID      INT NOT NULL,
    ConductorID     INT NULL,  -- opcional: quién reporta/entrega el vehículo
    Fecha           DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME()),
    Tipo            VARCHAR(60) NOT NULL,
    Costo           DECIMAL(12,2) NOT NULL CHECK (Costo >= 0),
    Notas           NVARCHAR(400) NULL,
    CONSTRAINT FK_Mant_Veh FOREIGN KEY (VehiculoID) REFERENCES gt.Vehiculos(VehiculoID),
    CONSTRAINT FK_Mant_Con FOREIGN KEY (ConductorID) REFERENCES gt.Conductores(ConductorID)
);

-- Índices útiles
CREATE INDEX IX_Mantenimientos_Vehiculo_Fecha ON gt.Mantenimientos (VehiculoID, Fecha DESC);
CREATE INDEX IX_Mantenimientos_Conductor_Fecha ON gt.Mantenimientos (ConductorID, Fecha DESC);
GO

-- 5) Datos de ejemplo (pequeños, claros)
INSERT INTO gt.Vehiculos (Placa, Modelo, Activo, Disponible)
VALUES
('EV-001','Nissan Leaf',1,1),
('EV-002','Hyundai Kona',1,1),
('EV-003','Tesla Model 3',1,1),
('EV-004','BYD Dolphin',1,1),
('EV-005','Renault Zoe',0,0); -- inactivo

INSERT INTO gt.Conductores (Nombre, Licencia, Activo)
VALUES
(N'Ana Rojas','C-123',1),
(N'Luis Mora','C-456',1),
(N'Paola Méndez','C-789',1);

-- Mantenimientos históricos (últimos y anteriores a 30 días)
DECLARE @Veh1 INT = (SELECT VehiculoID FROM gt.Vehiculos WHERE Placa='EV-001');
DECLARE @Veh2 INT = (SELECT VehiculoID FROM gt.Vehiculos WHERE Placa='EV-002');
DECLARE @Veh3 INT = (SELECT VehiculoID FROM gt.Vehiculos WHERE Placa='EV-003');

DECLARE @Con1 INT = (SELECT ConductorID FROM gt.Conductores WHERE Licencia='C-123');
DECLARE @Con2 INT = (SELECT ConductorID FROM gt.Conductores WHERE Licencia='C-456');

-- Hace 10 días
INSERT INTO gt.Mantenimientos (VehiculoID, ConductorID, Fecha, Tipo, Costo, Notas)
VALUES (@Veh1, @Con1, DATEADD(DAY,-10,SYSDATETIME()), 'Alineación', 80.00, N'Revisión rápida');

-- Hace 40 días
INSERT INTO gt.Mantenimientos (VehiculoID, ConductorID, Fecha, Tipo, Costo, Notas)
VALUES (@Veh2, @Con2, DATEADD(DAY,-40,SYSDATETIME()), 'Cambio llantas', 320.00, N'Llantas nuevas');

-- Hoy
INSERT INTO gt.Mantenimientos (VehiculoID, ConductorID, Tipo, Costo, Notas)
VALUES (@Veh3, @Con1, 'Chequeo general', 150.00, N'Sin hallazgos críticos');
GO

/* ============================================================
   6) Consultas solicitadas (JOIN / avanzadas)
   ============================================================ */

-- 6.1) Listar mantenimientos por conductor (JOIN conductor + mantenimiento + vehículo)
SELECT 
    c.ConductorID,
    c.Nombre,
    m.MantenimientoID,
    m.Fecha,
    m.Tipo,
    m.Costo,
    v.Placa,
    v.Modelo
FROM gt.Mantenimientos AS m
JOIN gt.Conductores  AS c ON c.ConductorID = m.ConductorID
JOIN gt.Vehiculos    AS v ON v.VehiculoID  = m.VehiculoID
ORDER BY c.Nombre, m.Fecha DESC;
GO

-- 6.2) Mostrar vehículos SIN mantenimiento en el último mes
-- (últimos 30 días respecto a SYSDATETIME())
SELECT v.VehiculoID, v.Placa, v.Modelo, v.Activo, v.Disponible, v.FechaAlta
FROM gt.Vehiculos AS v
WHERE NOT EXISTS (
    SELECT 1
    FROM gt.Mantenimientos AS m
    WHERE m.VehiculoID = v.VehiculoID
      AND m.Fecha >= DATEADD(DAY, -30, SYSDATETIME())
)
ORDER BY v.Placa;
GO

/* ============================================================
   7) Operaciones de conjuntos
   - Comparar vehículos activos vs. en mantenimiento reciente
   - Se usan CTEs dentro del MISMO batch para evitar errores (Msg 208)
   ============================================================ */

-- 7.1) UNION: activos o en mantenimiento reciente (últ. 30 días)
WITH Activos AS (
    SELECT Placa FROM gt.Vehiculos WHERE Activo = 1
),
EnMantoRec AS (
    SELECT DISTINCT v.Placa
    FROM gt.Mantenimientos AS m
    JOIN gt.Vehiculos     AS v ON v.VehiculoID = m.VehiculoID
    WHERE m.Fecha >= DATEADD(DAY, -30, SYSDATETIME())
)
SELECT Placa FROM Activos
UNION
SELECT Placa FROM EnMantoRec
ORDER BY Placa;
GO

-- 7.2) INTERSECT: activos QUE además estuvieron en mantenimiento reciente
WITH Activos AS (
    SELECT Placa FROM gt.Vehiculos WHERE Activo = 1
),
EnMantoRec AS (
    SELECT DISTINCT v.Placa
    FROM gt.Mantenimientos AS m
    JOIN gt.Vehiculos     AS v ON v.VehiculoID = m.VehiculoID
    WHERE m.Fecha >= DATEADD(DAY, -30, SYSDATETIME())
)
SELECT Placa FROM Activos
INTERSECT
SELECT Placa FROM EnMantoRec
ORDER BY Placa;
GO

-- 7.3) EXCEPT: activos que NO estuvieron en mantenimiento reciente
WITH Activos AS (
    SELECT Placa FROM gt.Vehiculos WHERE Activo = 1
),
EnMantoRec AS (
    SELECT DISTINCT v.Placa
    FROM gt.Mantenimientos AS m
    JOIN gt.Vehiculos     AS v ON v.VehiculoID = m.VehiculoID
    WHERE m.Fecha >= DATEADD(DAY, -30, SYSDATETIME())
)
SELECT Placa FROM Activos
EXCEPT
SELECT Placa FROM EnMantoRec
ORDER BY Placa;
GO

/* ============================================================
   8) Transacción: registrar mantenimiento + marcar no disponible
      con TRY...CATCH para asegurar consistencia
   ============================================================ */

-- Variables de ejemplo (ajusta la placa/licencia si deseas)
DECLARE @PlacaDemo      VARCHAR(15) = 'EV-001';
DECLARE @LicenciaDemo   VARCHAR(30) = 'C-123';
DECLARE @VehiculoDemoID INT = (SELECT VehiculoID FROM gt.Vehiculos WHERE Placa = @PlacaDemo);
DECLARE @ConductorDemoID INT = (SELECT ConductorID FROM gt.Conductores WHERE Licencia = @LicenciaDemo);

BEGIN TRY
    BEGIN TRAN;

    -- 1) Insertar mantenimiento
    INSERT INTO gt.Mantenimientos (VehiculoID, ConductorID, Tipo, Costo, Notas)
    VALUES (@VehiculoDemoID, @ConductorDemoID, 'Servicio programado', 120.00, N'Transacción demo');

    -- 2) Marcar vehículo como NO disponible temporalmente
    UPDATE gt.Vehiculos
    SET Disponible = 0
    WHERE VehiculoID = @VehiculoDemoID;

    COMMIT TRAN;
    PRINT 'Transacción OK: mantenimiento registrado y vehículo no disponible.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    PRINT 'Error en la transacción: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Comprobación rápida del efecto
SELECT v.Placa, v.Disponible
FROM gt.Vehiculos v
WHERE v.Placa IN ('EV-001','EV-002','EV-003');
GO
