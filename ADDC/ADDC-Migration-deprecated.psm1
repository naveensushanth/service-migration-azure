﻿Function Start-ADDCDeploymentProcess {

Param (
    [Parameter(Mandatory=$true)]
    [string]$Domain,
    [Parameter(Mandatory=$true)]
    [string]$DNS,
    [Parameter(Mandatory=$true)]
    [string]$Password,
    [Parameter(Mandatory=$true)]
    [string]$ComputerName
)

    $DomainCredential = Get-CredentialObject -domain $Domain
    $Credential = Get-CredentialObject

    $CfgDns = {
    
        Param(
            $DNS,
            $Domain,
            $ComputerName,
            $DomainCredential
        )
        
        Function Configure-DomainDNS {

        <#
.SYNOPSIS
  Configure DNS adresses on local interface and join specified domain.

.DESCRIPTION
  The function configures the first available local interface that has a IPv4-address,
  and updates the DNS address to point towards the specified DNS. Finally it will attempt
  to join the local computer to the specified domain.

.PARAMETER DNS
    IP address that points to a DNS that can resolve the domain name.

.PARAMETER Domain
    Domain name that is to be joined by the localhost.

.PARAMETER DomainCredential
    Credential object carrying credentials with privileges to join the specified domain.

.INPUTS
  None

.OUTPUTS
  The function writes to a log file defined with the 
  service-migration-azure runtime variable $sLogFile.

.NOTES
  Version:        1.0
  Author:         Emil Claussen
  Purpose/Change: Initial script development
  
.EXAMPLE
  Configure-DomainDNS -DNS 8.8.8.8 -Domain AMSTEL -DomainCredential (Get-Credential)
#>

        Param(
        $DNS, 
        $Domain, 
        $ComputerName,
        $DomainCredential
        )

        Process {
            Try {
                $interface = Get-NetAdapter | Select ifIndex,InterfaceDescription
                #Logging
                Write-Host "Configuring DNS on adapter $($interface[0].InterfaceDescription)"

                Set-DnsClientServerAddress -InterfaceIndex $interface.ifIndex -ServerAddresses($DNS)
                    
                $DNSClient = Get-DnsClientServerAddress | Select InterfaceIndex,AddressFamily,ServerAddresses
                foreach ($element in $DNSClient) {
                    If ($element.InterfaceIndex -eq $interface[0].ifIndex -and $element.AddressFamily -eq 2){
                            #Logging
                            Write-Host $element.ServerAddresses
                    }
                }
        
            } Catch {
                Write-Host "DNS config failed:"
                Write-Host $_.Exception.Message
            }
            Try {
                Add-Computer -ComputerName $ComputerName -DomainName $domain -Credential $DomainCredential
            } Catch {
                Write-Host $_.Exception.Message
            }
        }
        }

    Configure-DomainDNS -DNS $DNS -Domain $Domain -ComputerName $ComputerName -DomainCredential $DomainCredential
    }
    
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $CfgDns -ArgumentList $DNS,$Domain,$ComputerName,$DomainCredential -Credential $Credential
    Reboot-and-Deploy -ComputerName $ComputerName -DomainCredential $DomainCredential -LocalCredential $Credential -Password $Password -functionDeployDC ${Function:Deploy-DomainController}

    Start-RebootCheck -ComputerName $ComputerName -DomainCredential $DomainCredential

    $postDep = {

        Param(
            $FunctionMoveFSMO
        )

            Start-sleep -s 180
            
            New-Item -Path function: -Name Move-OperationMasterRoles -Value $FunctionMoveFSMO

            #repadmin /kcc

            $FSMO = netdom query fsmo
            $Master = $FSMO[0] | % { $_.Split(" ")} | select -last 1 | % {$_.Split(".")}
            $Root = [ADSI]"LDAP://RootDSE"
            $DomainDN = $Root.Get("rootDomainNamingContext")

            repadmin /replicate $env:COMPUTERNAME $Master[0] $DomainDN /full

            Move-OperationMasterRoles -ComputerName $env:COMPUTERNAME
        }

    Invoke-Command -ComputerName $ComputerName -ScriptBlock $postDep -ArgumentList ${Function:Move-OperationMasterRoles} -Credential $DomainCredential
    
    Write-Output "End of script"
} 

Workflow Reboot-and-Deploy {

Param(
    [Parameter(Mandatory=$true)] 
    [string]$Password,
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    [Parameter(Mandatory=$true)] 
    [System.Management.Automation.PSCredential]
    $LocalCredential,
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.PSCredential]
    $DomainCredential,
    [Parameter(Mandatory=$true)]
    $FunctionDeployDC
)

    Restart-Computer -PSComputerName $ComputerName -Protocol WSMan -Wait -Force -PSCredential $LocalCredential

    InlineScript {
     
        $depDC = {

        Param (
            $DeployFunction,
            $DomainPassword,
            $DomainCredential
        )

        New-Item -Path function: -Name Deploy-DomainController -Value $DeployFunction

        Deploy-DomainController -pw $DomainPassword -domaincred $DomainCredential

        }
              
        Invoke-Command -ComputerName $using:ComputerName -ScriptBlock $depDC -ArgumentList $using:FunctionDeployDC,$using:Password,$using:DomainCredential -Credential $using:DomainCredential

    }
}

Function Deploy-DomainController {

Param($pw, $domaincred)

Begin {
    Add-WindowsFeature -Name “ad-domain-services” -IncludeAllSubFeature -IncludeManagementTools
    Import-Module ADDSDeployment
}

Process {
    $password = ConvertTo-SecureString $pw -AsPlainText -Force
    Try {
    #Log
    Write-Output "Installing domain and promoting DC"
    Install-ADDSDomainController -DomainName (Get-WmiObject win32_computersystem).Domain -InstallDns -SafeModeAdministratorPassword $password -Credential $domaincred -Force
    } Catch {
        Write-Output "Install failed:"
        Write-Output $_.Exception.Message
    } 
}
}

Function Move-OperationMasterRoles {
Param(
    $ComputerName
)
<# 
########################################################
Commmented out for possible later use with legacy support
Updating the NTDS Object DNS hostname for FSMO migration.
########################################################
    Try {
        $siteName = nltest /server:TESTSRV-2016 /dsgetsite
        $configNCDN = (Get-ADRootDSE).ConfigurationNamingContext
        $siteContainerDN = (“CN=Sites,” + $configNCDN)
        $serverContainerDN = “CN=Servers,CN=” + $siteName[0] + “,” + $siteContainerDN
        $serverReference = Get-ADObject -SearchBase $serverContainerDN –filter {(name -eq $ComputerName)} -Properties "DistinguishedName"
        $fqdns = $ComputerName + "." + (Get-ADDomain).DNSRoot    

        Set-ADObject -Identity $serverReference.DistinguishedName -Add @{dNSHostName=$fqdns}
    } Catch {
    } #>
    Try {
        Move-ADDirectoryServerOperationMasterRole -Identity $ComputerName -OperationMasterRole 0,1,2,3,4 -Confirm:$false -ErrorAction Stop
        Write-Output "All Operation Master roles were successfully migrated."
    } Catch {
            Write-Output $_.Exception.message
    }
}

Function Start-GpoCopy {
Param ($DNS, $Credential )
    Try {
        New-Item -Name "Configure-ClientDNS.ps1" -Path '.\Support\GPO\{23479CB6-4EC3-4B0E-8DF3-A5F046CC623F}\DomainSysvol\GPO\Machine\Scripts\Startup\' `
        -Value "Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter)[0].ifIndex -ServerAddresses $DNS" -ErrorAction Stop
    } Catch {
        
    }

    New-PSDrive -PSProvider FileSystem -Name "share" -Root \\158.38.43.115\C$\Share -Credential $Credential -ErrorAction Stop
    Copy-Item '.\Support\GPO\' -Destination share:\ -Recurse
}

Function Start-GpoImport {
Param ($Credential)
    New-PSDrive -PSProvider FileSystem -Name "share" -Root \\158.38.43.115\C$\Share -Credential $Credential -ErrorAction Stop
    Copy-Item 'share:\GPO' -Recurse -Destination C:\GPO
    $GpoName = "Post-Migration DNS GPO"
    New-GPO -Name $GpoName
    Import-GPO -BackupGpoName "Post-Migration DNS Update" -Path C:\GPO -TargetName $GpoName
    New-GPLink -Name $GpoName -Target "OU=DNS Update,DC=amstel,DC=local"
}