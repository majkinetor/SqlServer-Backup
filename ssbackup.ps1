#Version 1.0

#Requires -Module SqlServer

param(
    [ValidateSet('Full', 'Diff', 'TLog')]
    [string] $Type = 'Full',

    # If provided, full backup will be restored to destination immediately
    [switch] $Restore,

    # No backup will be done and Type will be used as info about what to restore
    #  The latest full and diff backups and last tlog chain will be restored depending on Type
    [switch] $RestoreOnly,

    # Run continuously and apply strategy defined in config file
    [switch] $Strategy
)

Get-Item $PSScriptRoot\inc\*.ps1 | % { . $_ }

$ErrorActionPreference = 'STOP'

New-Item -Type Directory $Cfg.Paths.LocalPath -ErrorAction ignore

if ($RestoreOnly) { return New-Restore -Type $Type }
if (!$Strategy) {
    $backupFileName = New-Backup $Type
    Log "Backup created:" $backupFileName
    if ($Restore) {
        if ($Type -ne 'Full') { throw "Immediate restore works only with FULL backup" }
        New-Restore $backupFileName $Type
    }
    return
}

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

Log "Executing strategy"

$Strat = $Cfg.Strategy
Log "Waiting for next scheduled minute: $($Strat.Scheduler.Minutes)`n"
while (1) {
    $now = Get-Date
    if ($lastMinute -eq $now.Minute -or $now.Minute -notin $Strat.Scheduler.Minutes) {
        Start-Sleep 10
        continue
    }
    $lastMinute = $now.Minute
    $backupDone = $false

    Log "Getting database info from the source server"
    $db = Get-SourceDatabase
    Log ("Database '{0}' owned by '{1}' with '{2}' recovery model and current size of '{3}'" -f $db.Name, $db.Owner, $db.RecoveryModel, $db.Size)
    Log "  last full:"  $db.LastBackupDate.ToString('s')
    Log "  last diff:"  $db.LastDifferentialBackupDate.ToString('s')
    Log "  last tlog:"  $db.LastLogBackupDate.ToString('s')

    $fullAge = ($now - $db.LastBackupDate).TotalMinutes + $Strat.Tolerance
    $diffAge = ($now - $db.LastDifferentialBackupDate).TotalMinutes + $Strat.Tolerance
    $tlogAge = ($now - $db.LastLogBackupDate).TotalMinutes + $Strat.Tolerance
    $fullDue = $fullAge -gt $Strat.Full.BackupAfter
    $diffDue = $diffAge -gt $Strat.Diff.BackupAfter
    $tlogDue = $tlogAge -gt $Strat.TLog.BackupAfter

    if ($fullDue) {
        Log "Full backup is due"
        if ($now.Hour -in $Strat.Full.BackupHours) {
            $_ = New-Backup Full
            if ($_ -and $Strat.Restore.Full) { New-Restore -Type Full }
            $backupDone = $true
        } else { Log "  waiting for backup hours $($Strat.Full.BackupHours)" }
    }

    if ($diffDue -and !$backupDone) {
        Log "Diff backup is due"
        $_ = New-Backup Diff
        if ($_ -and $Strat.Restore.Diff) { New-Restore -Type Diff }
        $backupDone = $true
    }

    if ($tlogDue -and !$backupDone) {
        Log "TLog backup is due"
        $_ = New-Backup TLog
        if ($_ -and $Strat.Restore.TLog) { New-Restore -Type TLog }
        $backupDone = $true
    }

    if (!$backupDone) { Log "Nothing is due" }

    Clear-LocalStore
    Log "Waiting for next scheduled minute: $($Strat.Scheduler.Minutes)`n"
}
