param
(
	$Username,
	$Password,
	$Credentials,
	$AuxUsername,
	$AuxPassword,
	$AuxCredentials,
	$ConfigurationParameter
)
$obj = New-Object -Type PSCustomObject
$obj | Add-Member -Type NoteProperty -Name "Id|String" -Value "COMPUTER-001"
$obj | Add-Member -Type NoteProperty -Name "objectClass|String" -Value "device"
$obj | Add-Member -Type NoteProperty -Name "sAMAccountName|String" -Value "PC-DEVICE-001$"
$obj | Add-Member -Type NoteProperty -Name "displayName|String" -Value "Computer Device Name"
$obj | Add-Member -Type NoteProperty -Name "extensionAttribute1|String" -Value "Custom Value"
$obj