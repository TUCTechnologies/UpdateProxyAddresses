# When set to $true, then no actions will be taken, only tested
# When set to $false, script will perform actions
$WhatIfPreference = $true
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
		[string]$addressToAdd
	)
	
	# Check if the address has already been added
	$alreadyAdded = 0
	ForEach($userAddress in $user.proxyAddresses) {
		If($addressToAdd -eq $userAddress) {
			$alreadyAdded = 1
			WriteLog ($user.samAccountName + " already has a proxy address of: " + $addressToAdd)
			break
		}
	}
	# If the address hasn't been added, do so
	If($alreadyadded -eq 0) {
		Set-ADUser -Identity $user.samAccountName -add @{proxyAddresses=($addressToAdd)}
		WriteLog ($user.samAccountName + " now has a proxy address of: " + $addressToAdd)
	}
}

$Users = Import-Csv -Path ".\users.csv"
$upnSuffixes = Get-ADForest | Select UPNSuffixes -ExpandProperty UPNSuffixes
ForEach ($User in $Users) {
	
	$UPN = ($User."User principal name")
	$username = $UPN.split("@")[0]
	$upnSuffix = $UPN.split("@")[1]
	
	# Get the user from Active Directory if it exists, move on if it doesn't
	$ADUser = Try { 
			Get-ADUser -Identity $username -Properties proxyAddresses
		} 
		Catch {
			WriteLog ("The username '$username' does not exist in Active Directory... continuing.")
			Continue
		}
	
	# Update the UPN if needed
	If($ADUser.UserPrincipalName -ne $UPN) {
		Set-ADUser -Identity $username -UserPrincipalName $UPN
		WriteLog ($username + " now has UPN of: " + $UPN)
	}
	
	# Update AD account with proxy addresses
	$proxyAddressesToUpdate = ($User."Proxy addresses").split("+")
	ForEach($proxyAddress in $proxyAddressesToUpdate) {
		If($proxyAddress -like "*onmicrosoft.com*") {
			# skip the addresses with onmicrosoft.com
			Continue
		}
		Else {
			updateProxyAddress $ADUser $proxyAddress
		}
	}
}

$host.ui.RawUI.ForegroundColor = "White"
