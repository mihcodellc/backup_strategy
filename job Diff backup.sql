--enable database mail
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE;
GO


--config database mail
EXECUTE msdb.dbo.sysmail_configure_sp 'DatabaseMailExeMinimumLifeTime',3600 
EXECUTE msdb.dbo.sysmail_configure_sp 'ProhibitedExtensions','exe,dll,vbs,js'
EXECUTE msdb.dbo.sysmail_configure_sp 'LoggingLevel', 2; --3 for troubleshooting 

-- create database mail account
IF NOT EXISTS(select '1' from msdb.dbo.sysmail_account where name = 'ONS_DEV')
EXECUTE msdb.dbo.sysmail_add_account_sp @account_name = 'ONS_DEV', 
										@email_address = 'onsdev@gmail.net',@Display_name='ONS DEV',
										@mailserver_name = 'smtp.gmail.com';
GO
--create operator 24/7
IF NOT EXISTS(select '1' from msdb.dbo.sysoperators where name = 'ONS_DEV')
EXEC  msdb.dbo.sp_add_operator @name=N'ONS_DEV', 
		@enabled=1, 
		@weekday_pager_start_time=0, 
		@weekday_pager_end_time=235900, 
		@saturday_pager_start_time=0, 
		@saturday_pager_end_time=115900, 
		@sunday_pager_start_time=0, 
		@sunday_pager_end_time=235900, 
		@email_address=N'onsdev@gmail.net', 
		@pager_address=N'onsdev@gmail.net' 
GO

/****** Object:  Job []     ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

DECLARE @jobId BINARY(16)

--Create a job
IF NOT EXISTS(select '1' from msdb.dbo.sysjobs_view WHERE name='BackupThemUp_Diff') BEGIN
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'BackupThemUp_Diff', 
			@enabled=1, 
			@notify_level_eventlog=3, --  2(default) on failure --3 Always  --1 on success : in Microsoft Windows application log
			@notify_level_email=3,    --  2(default) on failure --3 Always  --1 on success
			@description=N'Backup the selected databases every hour from 6am-6pm. ', 
			@notify_email_operator_name=N'ONS_DEV', 
			@job_id = @jobId OUTPUT
	--test sucess creation of the job
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	--add a step
	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, 
			@step_name=N'Step1', 
			@step_id=1, 
			@cmdexec_success_code=0, --code to use when success
			@on_success_action=1, --1  Quit with success --3 Go to the next step  --2 Quit with failure --4 Go to step @on_success_step_id
			@on_success_step_id=0, 
			@on_fail_action=2,    --1  Quit with success --3 Go to the next step  --2 Quit with failure --4 Go to step @on_fail_step_id
			@on_fail_step_id=0, 
			@retry_attempts=3, 
			@retry_interval=2,    -- in minutes
			@os_run_priority=0, @subsystem=N'TSQL', 
    		@command=N'exec master.dbo.[sp_DatabaseBackup] @Databases=''%Thinkhealth%, msdb'', @Directory=''C:\Backups\'',
						  @BackupType=''DIFF'', @Verify=''Y'', @Compress=''Y'', @CheckSum=''Y'', @NoRecovery=''N'', @DirectoryStructure = NULL,
						  @FileName=''{DatabaseName}_{BackupType}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}'',
						  @FileExtensionFull=''bak'', @FileExtensionDiff=''DIF'', @FileExtensionLog=''trn'', @Init=''N'', @LogToTable=''Y'', @ChangeBackupType=''Y'',
						  @Execute=''Y'',  @SafePlaceForCopy=''C:\Backups\back\''', 
			@flags=32  -- Write all output to job history
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	--add the step to a job
	EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	--schedule
	EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, 
			@name=N'Schedule_BackupThemUp_Diff', 
			@enabled=1, 
			@freq_type=4,    -- 1 Once 4 Daily 8 Weekly 16 Monthly 32 (monthly relative) 64 When Agent starts
			@freq_interval=1, 
			@freq_subday_type=8, -- 0x1 specified time  0x4 Minutes	 0x8 Hours
			@freq_subday_interval=1, --periods to occur between each execution
			@freq_relative_interval=0, 
			@active_start_date=20191101, 
			@active_end_date=99991231, 
			@active_start_time=060000, --HHMMSS
			@active_end_time=180000 --, --HHMMSS
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	-- target a server with a job
	EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END
ELSE
		SELECT 'BackupThemUp_Diff exists. Check if its config match your requirements ' PAY_ATTENTION

-- create an alert for specific severity, id or text content not for a job
-- a job associated with alert will be used in response to the alert  
-- report any error which occurs during the execution of the job 
IF NOT EXISTS(select '1' from msdb.dbo.sysalerts where severity=16) BEGIN
	EXEC msdb.dbo.sp_add_alert @name=N'Alert_Severity16', --sysname type
			@message_id=0, -- msgId set -> severity =0
			@severity=16, -- severity set -> msgId=0
			@enabled=1, 
			@delay_between_responses=0, 
			@include_event_description_in=3 -- 1 email  --2 pager --4 net send --values combined with an OR
	-- assign alert to an operator
	EXEC msdb.dbo.sp_add_notification  @alert_name = N'Alert_Severity16',  
	 @operator_name = N'ONS_DEV',  
	 @notification_method = 1 ;  -- 1 email  --2 pager --4 net send --values combined with an OR
END
ELSE
	SELECT 'Alert_Severity16 exists under another name. Check if its config match your requirements ' PAY_ATTENTION

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
 

COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



 
 ---************CHECK AND DELETE PROFILE OR EMAIL ACCOUNT IN DATABASE MAIL
EXECUTE msdb.dbo.sysmail_help_profile_sp;  -- LIST PROFILE
	--EXECUTE msdb.dbo.sysmail_delete_profile_sp  @profile_name = 'Monktar' ;  
	--IF NOT EXISTS(select * from msdb.dbo.sysmail_profile where name = 'ONS_DEV')
EXECUTE msdb.dbo.sysmail_help_account_sp ; -- LIST ACCOUNT
	--EXECUTE msdb.dbo.sysmail_delete_account_sp @account_name = 'ONS_DEV' ;  
EXECUTE msdb.dbo.sp_help_operator  
	--EXEC msdb.dbo.sp_delete_operator @name = 'ONS_DEV' ;  
EXECUTE msdb.dbo.sp_help_alert
	--EXEC msdb.dbo.sp_delete_alert  @name = N'Alert_BackupThemUp_Full' ;  

