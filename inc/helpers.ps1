function cred ($u, $p){$s = [securestring]::new(); [char[]]$p | % { $s.AppendChar($_) }; [pscredential]::new($u, $s) }

function Get-SourceDatabase {
    $params = @{
        ServerInstance  = $Cfg.Source.ServerInstance
        Database        = $Cfg.Source.Database
        Credential      = cred $Cfg.Source.Username $Cfg.Source.Password
    }

    Get-SqlDatabase @params
}

function New-Backup( [string] $Type )
{
    Log "Executing $Type backup"

    $backupDirPath  = $Cfg.Paths.RemotePath
    $backupFileName = "$(Get-Date -Format 'yyyy-MM-ddTHH_mm_ss') $($Cfg.Source.Database)"
    
    $params = @{
        BackupAction      = 'Database'
        Verbose           = $true
        CompressionOption = 'On'
    }
    switch ($Type) 
    {
        'Full' { $backupFileName += '.full' }
        'Diff' { $backupFileName += '.diff'; $params.Incremental  = $true }
        'TLog' { $backupFileName += '.tlog'; $params.BackupAction = 'Log' }
    }
    $params.BackupFile = Join-Path $backupDirPath $backupFileName
    Get-SourceDatabase | Backup-SqlDatabase @params 
    
    Log "Moving file to local store: $backupFileName"
    $shareBackupPath = Join-Path $Cfg.Paths.RemotePathDrive $backupFileName
    $localBackupPath = Join-Path $Cfg.Paths.LocalPath $backupFileName
    Move-Item $shareBackupPath $localBackupPath

    $backupFileName
}

function New-Restore ( [string] $BackupFileName, [string] $Type )
{
    function set-offline {
        log "Setting database offline immediatelly"
        Invoke-SqlCmd -ServerInstance $serverInstance -Credential $credential -Query "
            ALTER DATABASE [$database]
            SET OFFLINE WITH ROLLBACK IMMEDIATE
        "
    }

    $serverInstance = $Cfg.Destination.ServerInstance
    $credential     = cred $Cfg.Destination.Username $Cfg.Destination.Password
    $database       = $Cfg.Destination.Database

    log "Restore backup to '$serverInstance', database '$database'"

    $params = @{
        ServerInstance   = $serverInstance
        Database         = $database
        Credential       = $credential
        BackupFile       = ''
        AutoRelocateFile = $true
        ReplaceDatabase  = $true
        NoRecovery       = $false   # must be true to restore multiple backup files in order
        #Verbose          = $true
    }

    if ($BackupFileName) {
        log "Restore single backup: $BackupFileName"
        $params.BackupFile = Join-Path $Cfg.Paths.LocalPath $BackupFileName 
        set-offline
        Restore-SqlDatabase @params
        return
    }

    Log "Restore latest backups from the local store"

    $latestBackups = get-latest-backups
    if (!$latestBackups) { log "No backups available"; return }

    set-offline
    for ($i=1; $i -le $latestBackups.Count; $i++) {
        $params.NoRecovery = $i -ne $latestBackups.Count
        $params.BackupFile = $latestBackups[$i-1].FullName
        log "  restoring" $params.BackupFile
        Restore-SqlDatabase @params
    }

    log "Restore Completed"
}

function get-latest-backups() {
    function filename-date($File) { $File.Name.Replace("_", ":").Split(' ') | Select-Object -First 1 | Get-Date }

    Log "Finding latest backups in the local store"

    $fullBackupFile = Get-ChildItem $Cfg.Paths.LocalPath -Filter *.full | Select-Object -Last 1
    if (!$fullBackupFile) { return }
    $fullBackupDate = filename-date $fullBackupFile

    $diffBackupFile = Get-ChildItem $Cfg.Paths.LocalPath -Filter *.diff | Select-Object -Last 1 | ? { (filename-date $_) -gt $fullBackupDate }
    $diffBackupDate = if ($diffBackupFile) { filename-date $diffBackupFile }

    $date = if ($diffBackupDate) { $diffBackupDate } else { $fullBackupDate }
    [array] $tlogBackupFiles = Get-ChildItem $Cfg.Paths.LocalPath -Filter *.tlog | ? { (filename-date $_) -gt $date }

    log "  Full:" $fullBackupFile.Name
    log "  Diff:" $diffBackupFile.Name
    log "  TLog:" "$($tlogBackupFiles.Name -join ', ')"
    
    $lastBackups = @($fullBackupFile)
    if ($Type -eq 'Diff' -and $diffBackupFile)  { $lastBackups += $diffBackupFile }
    if ($Type -eq 'TLog' -and $tlogBackupFiles) { $lastBackups += $tlogBackupFiles }

    log "$Type restore requested, executing" $lastBackups.Count "backup files"

    return $lastBackups
}

function Clear-LocalStore {
    foreach ($type in 'full', 'diff', 'tlog') {
        [array] $files = Get-ChildItem $Cfg.Paths.LocalPath -Filter *.$type
        $keep  = $Cfg.Strategy.$type.Keep
        $extra = $files.Count - $keep 
        if ($extra -gt 0) {
            Log "Removing $extra expired files"
            $files | select -First $extra | Remove-Item -Verbose
        }
    }
}