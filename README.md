# SQL Server Backup Script

This script provides a way to backup the MS SQL Server database with subsequent restoration. The script is hosted on the server which hosts the restored database and accesses the remote database via SMB share. The script runs continuously and executes backup strategy defined in the config file.

## Setup

The entire directory that contains the script should be copied to the server that will host the restored database. None of the servers hosting MS SQL Server need to be part of the domain.

1. Setup configuration in `config.ps1` (later mentioned as `$Config`)
2. On the remote (*Source*) server:
    1. Create the directory specified in `$Config.Paths.RemotePath`
    2. Share this directory and add full rights to `Authenticated Users` (use the [script](#remote-server) below)
        - The share should be encrypted for maximum security
3. On the local (*Destination*) server:
    1. Access the remote share previously created and map it to the drive specified in `$Config.Paths.RemotePathDrive`.
        -  Specify *reconnect at logon* and use explicit credentials of the remote local user (use the [script](#local-server) below)
    2. Specify the local directory to move the remote backups into in `$Config.Paths.LocalPathDrive`.
        - If it doesn't exist, it will be automatically created.
    3. Install PowerShell SQLServer module: `Install-Module SqlServer -Force`

## Usage

```ps1
# Create full backup once and exit
./ssbackup.ps1

# Create differential backup
./ssbackup.ps1 -Type diff

# Create transaction log backup
./ssbackup.ps1 -Type tlog

# Create full backup and restore it to localhost immediately
./ssbackup.ps1 -Restore

# Do not backup source, but restore to the destination latest locally stored full backup
./ssbackup.ps1 -RestoreOnly

# Do not backup source, but restore to the destination latest locally stored backups of TLog type.
#  This will first restore the latest full backup, then the latest newer diffferential backup if it exists
#  then all the latest newer transaction log backups if they exist
./ssbackup.ps1 -RestoreOnly -Type Tlog

# Run continuously strategy defined in config file
./ssbackup.ps1 -Strategy
```

## Setup scripts

### Remote server

Execute on the remote server, in the administrative shell:

```ps1
$SharePath = "C:\SqlServer-Backup"      # Use $Config.Paths.RemotePath
New-Item -ItemType Directory $SharePath

$dirName = Split-Path $SharePath -Leaf
$params = @{
    Name        = $dirName
    Path        = $SharePath
    FullAccess  = 'Authenticated Users'
    EncryptData = $true
}
New-SmbShare @params
```

### Local server

Execute in the administrative shell, in the script directory:

```ps1
$Config = . .\config.ps1
$creds = Get-Credential Administrator
New-PSDrive -Name $Config.Paths.RemotePathDrive -PSProvider FileSystem -Root $Config.Paths.RemotePath -Persist -Credentials $creds
```