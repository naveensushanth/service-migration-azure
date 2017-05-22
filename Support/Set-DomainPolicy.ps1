﻿Param(
    $DomainName,
    $Username,
    $Password
)

Set-ExecutionPolicy Unrestricted

$SecureString = ConvertTo-SecureString $Password -AsPlainText -Force

$Credential = New-Object System.Management.Automation.PSCredential($Username,$SecureString)

Add-Computer -LocalCredential $Credential -DomainName $DomainName -Credential $Credential

Enable-PSRemoting -Force

Set-Item wsman::localhost\Client\TrustedHosts -Value "*" -Force

Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -RemoteAddress Any