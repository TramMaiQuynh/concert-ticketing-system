-- ============================================================
-- 00_TestFramework.sql
-- Framework test nhe (khong can cai tSQLt).
-- Luu y: Moi lan goi sp_RunTest se chay trong BEGIN TRAN / ROLLBACK
--        rieng de khong lam nhiem du lieu.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

-- Tao bang luu ket qua (table temp tong session)
IF OBJECT_ID('tempdb..#TestResults') IS NOT NULL
    DROP TABLE #TestResults;

CREATE TABLE #TestResults (
    TestID           INT IDENTITY(1,1) PRIMARY KEY,
    TestSuite        VARCHAR(255)  NOT NULL,
    TestName         VARCHAR(255)  NOT NULL,
    Status           VARCHAR(10)   NOT NULL,  -- PASS | FAIL
    ExpectedBehavior VARCHAR(255),
    ActualMessage    NVARCHAR(MAX),
    ExecutedAt       DATETIME2    DEFAULT SYSDATETIME()
);
GO

-- ============================================================
-- sp_RunTest: Chay 1 test case, catch loi, ghi vao #TestResults
--   @ExpectedResult : 'SUCCESS' | 'ERROR'
--   @ExpectedErrCode: Error number mong doi khi ERROR (tuy chon)
--   @TestSQL        : T-SQL can thuc thi (NVARCHAR(MAX))
-- ============================================================
CREATE OR ALTER PROCEDURE sp_RunTest
    @TestSuite       VARCHAR(255),
    @TestName        VARCHAR(255),
    @ExpectedResult  VARCHAR(20),
    @ExpectedErrCode INT = NULL,
    @TestSQL         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @Status        VARCHAR(10)   = 'FAIL';
    DECLARE @ActualMessage NVARCHAR(MAX) = '';
    DECLARE @ErrCode       INT           = 0;

    BEGIN TRY
        BEGIN TRAN;
        EXEC sp_executesql @TestSQL;
        ROLLBACK TRAN;     -- luon rollback de khong lam ban du lieu test

        IF @ExpectedResult = 'SUCCESS'
        BEGIN
            SET @Status = 'PASS';
            SET @ActualMessage = 'OK - executed without error.';
        END
        ELSE
        BEGIN
            SET @Status = 'FAIL';
            SET @ActualMessage = 'Expected ERROR but executed successfully.';
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;

        SET @ErrCode       = ERROR_NUMBER();
        SET @ActualMessage = 'ErrCode=' + CAST(@ErrCode AS VARCHAR) + ' Msg: ' + ERROR_MESSAGE();

        IF @ExpectedResult = 'ERROR'
        BEGIN
            IF @ExpectedErrCode IS NULL OR @ErrCode = @ExpectedErrCode
                SET @Status = 'PASS';
            ELSE
            BEGIN
                SET @Status = 'FAIL';
                SET @ActualMessage = 'Expected ErrCode ' + CAST(@ExpectedErrCode AS VARCHAR)
                                   + ' but got ' + CAST(@ErrCode AS VARCHAR)
                                   + '. Msg: ' + ERROR_MESSAGE();
            END
        END
        ELSE
        BEGIN
            SET @Status = 'FAIL';
            SET @ActualMessage = 'Expected SUCCESS but got ' + @ActualMessage;
        END
    END CATCH

    -- In ra luon de de theo doi
    PRINT CASE @Status WHEN 'PASS' THEN '[PASS]' ELSE '[FAIL]' END
        + ' ' + @TestSuite + ' - ' + @TestName
        + CASE @Status WHEN 'FAIL' THEN ': ' + @ActualMessage ELSE '' END;

    INSERT INTO #TestResults (TestSuite, TestName, Status, ExpectedBehavior, ActualMessage)
    VALUES (@TestSuite, @TestName,
            @Status,
            'Expected: ' + @ExpectedResult + ISNULL(' ErrCode=' + CAST(@ExpectedErrCode AS VARCHAR), ''),
            @ActualMessage);
END;
GO


