$Password = 'P@ssw0rd'

@{
    # Source database for backups, can be on remote server
    Source = @{
        ServerInstance = '<remote-server>'
        Database = '<remote-db>'
        Username = 'sa'
        Password = $Password
    }

    # Destination database for restore, must be on the local server (Restore/RestoreOnly flags)
    Destination = @{
        ServerInstance = 'localhost'
        Database = '<local-db>'
        Username = 'sa'
        Password = $Password
    }

    Paths = @{
        RemotePath      = "C:\SqlServer-Backup"
        RemotePathDrive = "S:"
        LocalPath       = "C:\SqlServer-Backup\Backup"
    }

    # Strategy that is applied in continuous run with (Strategy flag)
    Strategy = @{
        Full = @{
            BackupHours  = 3..5         # Do backup between 03 and 05 out of 24 hours
            Keep         = 14           # How many full backup files to keep
            BackupAfter  = 24*60        # Number of minutes that must elapse from previous full backup.
                                        #   After this time has passed, backup will occur on next BackupHour
            # Archive = @{
            #     WeekDay = 7             # Keep on Sunday
            #     Keep    = 16            # Number of archive full backups to keep - 4 months
            # }
        }

        Diff = @{
            Keep        = 24
            BackupAfter = 60
        }

        TLog = @{
            Keep        = 100
            BackupAfter = 15
        }

        Scheduler = @{
            Minutes = 0,15,30,45      # Start actions on these minutes in each hour
        }

        Restore = @{                  # Specify how restores are done within strategy
            Full = $true
            Diff = $false
            TLog = $false
        }

        Tolerance = 1                 # Number of minutes to tolerate when determining age of backups
    }
}