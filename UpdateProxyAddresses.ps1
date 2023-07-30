# When set to $true, then no actions will be taken, only tested
# When set to $false, script will perform actions
$WhatIfPreference = $false
If($WhatIfPreference -eq $true) {
	$host.ui.RawUI.ForegroundColor = "Green"
	Write-Host "--- Script is in testing mode, no actions will be taken ---" -ForegroundColor Blue
}
Else {
	$host.ui.RawUI.ForegroundColor = "Yellow"
	Write-Host "!!! Script is in production mode, actions will be taken !!!" -ForegroundColor Blue
	$confirmation = Read-Host -Prompt "To have the script proceed, please enter YES"
	If($confirmation -ne "YES") { Write-Host "Confirmation was incorrect, exiting..."; $host.ui.RawUI.ForegroundColor = "White"; Exit }
}

# Write to log and console output
Function WriteLog {
	Param ([string]$LogString)
	$LogFile = ".\ADSyncUpdate.log"
	$Timestamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
	$LogMessage = "$Timestamp - $LogString"
	If($WhatIfPreference -eq $true) {
		Add-Content $LogFile -value ("--TEST-- " + $LogMessage) -WhatIf:$false
	}
	Else {
		Add-Content $LogFile -value ("--PROD-- " + $LogMessage)
		Write-Host $LogMessage
	}
}

# Update an ADUser object with a proxy address, either primary or not
Function updateProxyAddress {
	
	Param (
		[Microsoft.ActiveDirectory.Management.ADUser]$user,
		[string]$addressToAdd,
		[bool]$primaryAddress
	)
	
	# Check if the address has already been added
	$alreadyAdded = 0
	ForEach($userAddress in $user.proxyAddresses) {
		If($primaryAddress) {
			If(("SMTP:"+$addressToAdd) -eq $userAddress) {
				$alreadyAdded = 1
				WriteLog ($user.samAccountName + " already has a primary proxy address of: " + $addressToAdd)
				break
			}
		}
		Else {
			If(("smtp:"+$addressToAdd) -eq $userAddress) {
				$alreadyAdded = 1
				WriteLog ($user.samAccountName + " already has a proxy address of: " + $addressToAdd)
				break
			}
		}
	}
	# If the address hasn't been added, do so
	If($alreadyadded -eq 0) {
		If($primaryAddress) {
			Set-ADUser -Identity $user.samAccountName -add @{proxyAddresses=("SMTP:"+$addressToAdd)}
			WriteLog ($user.samAccountName + " now has a primary proxy address of: " + $addressToAdd)
		}
		Else {
			Set-ADUser -Identity $user.samAccountName -add @{proxyAddresses=("smtp:"+$addressToAdd)}
			WriteLog ($user.samAccountName + " now has a proxy address of: " + $addressToAdd)
		}
	}
}

$Users = Import-Csv -Path ".\ADSync.csv"
$upnSuffixes = Get-ADForest | Select UPNSuffixes -ExpandProperty UPNSuffixes
ForEach ($User in $Users) {
	
	# Get the AD account
	$ADUser = Get-ADUser -Identity $User.username -Properties proxyAddresses
	
	# Update the UPN
	# Make sure the UPN to change to has an existing UPN suffix
	$suffixFound = $false
	$suffixToCheck = $User.domain	
	ForEach($suffix in $upnSuffixes) {
		If($suffix -eq $suffixToCheck) { $suffixFound = $true; break }
	}
	
	If([bool][int]$User.primaryAddress -eq $true) {
		If($suffixFound -eq $false) {
			WriteLog ("The suffix of '$suffixToCheck' does not exist, " + $User.username + " will not be changed")
			Continue
		}
		
		$UPN = $User.username + "@" + $User.domain
		If($ADUser.UserPrincipalName -ne $UPN) {
			Set-ADUser -Identity $User.username -UserPrincipalName $UPN
			WriteLog ($User.username + " now has UPN of: " + $UPN)
		}
	}
	
	# Update proxy addresses if needed and the suffix exists
	If($suffixFound) {
		updateProxyAddress $ADUser $User.proxyAddress ([int]$User.primaryAddress)
	}
	Else {
		WriteLog "The suffix of " + $suffixToCheck + " doesn't exist, not adding the proxy address of: " + $User.proxyAddress
	}
}

$host.ui.RawUI.ForegroundColor = "White"
