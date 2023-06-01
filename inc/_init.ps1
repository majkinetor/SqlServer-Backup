try {Stop-Transcript} catch {}

$now     = Get-Date
$subdir  = $now.ToString('yy-MM-dd')
$fn      = $now.ToString('yy-MM-dd HH-mm-ss-fffffff')
$logPath = Join-Path (Join-Path Logs $subdir) "$fn.log"
Start-Transcript $PSScriptRoot\..\$logPath

$Cfg = . $PSScriptRoot\..\config.ps1


function Log {
    if (!$script:StartDate) { $script:StartDate = Get-Date }

    $now     = Get-Date
    $elapsed = $now - $StartDate
    $log = '{0:s} [{1:hh\:mm\:ss}]    {2}' -f $now, $elapsed, "$args"
    Write-Host $Log
}
