﻿<#
Installation script by dbatools
http://dbatools.io
(c) 2017 dbatools / Chrissy LeMaire
#>

Remove-Module dbatools -ErrorAction SilentlyContinue
$url = 'https://github.com/ebc92/service-migration-azure/archive/master.zip'
$path = Join-Path -Path 'C:\' -ChildPath 'service-migration-azure'
$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
$zipfile = "$temp\service-migration-azure.zip"

if (!(Test-Path -Path $path)){
	Write-Output "Creating directory: $path"
	New-Item -Path $path -ItemType Directory | Out-Null 
} else { 
	Write-Output "Deleting previously installed module"
	Remove-Item -Path "$path\*" -Force -Recurse 
}

Write-Output "Downloading archive from github"
try
{
	Invoke-WebRequest $url -OutFile $zipfile
} catch {
   #try with default proxy and usersettings
   Write-Output "Probably using a proxy for internet access, trying default proxy settings"
   (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
   Invoke-WebRequest $url -OutFile $zipfile
}

# Unblock if there's a block
Unblock-File $zipfile -ErrorAction SilentlyContinue

Write-Output "Unzipping"
# Keep it backwards compatible
$shell = New-Object -COM Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($temp)
$destinationFolder.CopyHere($zipPackage.Items(), 0x14)

Write-Output "Cleaning up"
Move-Item -Path "$temp\service-migration-azure-master\*" $path
Remove-Item -Path "$temp\service-migration-azure-master" -Recurse
Remove-Item -Path $zipfile

Import-Module "$path\ADDC\ADDC-Migration.psm1" -Force
Import-Module "$path\MSSQL\MSSQL-Migration.psm1" -Force