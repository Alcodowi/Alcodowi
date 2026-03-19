# Import Script for AD Devices
<#
.SYNOPSIS
    This script imports Active Directory devices into a Metaverse.

.DESCRIPTION
    The script retrieves device data from Active Directory and imports them into the Metaverse.
    It exports sAMAccountName, displayName, and extensionAttribute1.

.PARAMETER Username
    The username specified in the Connectivity section of the MA.

.PARAMETER Password
    The password specified in the Connectivity section of the MA.

.PARAMETER Credentials
    The username and password as a PSCredential object.

.PARAMETER AuxUsername
    The auxiliary username specified in the Connectivity section of the MA.

.PARAMETER AuxPassword
    The auxiliary password specified in the Connectivity section of the MA.

.PARAMETER AuxCredentials
    The auxiliary username and password as a PSCredential object.

.PARAMETER OperationType
    The type of import operation ('Full' or 'Delta').

.PARAMETER UsePagedImport
    A boolean indicating whether this is a paged import.

.PARAMETER ImportPageNumber
    The current page number during import operations.

.PARAMETER PageSize
    The maximum number of objects to return in a paged import.

.PARAMETER Schema
    A PSCustomObject specifying the schema for the MA.

.OUTPUTS
    Hash table objects matching the schema with sAMAccountName, displayName, and extensionAttribute1.

.EXAMPLE
    .\import.ps1 -Username "admin" -Password "pass" -OperationType "Full" -Schema $schema
#>

param(
    [string]$Username,
    [string]$Password,
    [pscredential]$Credentials,
    [string]$AuxUsername,
    [string]$AuxPassword,
    [pscredential]$AuxCredentials,
    [string]$OperationType = 'Full',
    [bool]$UsePagedImport = $false,
    [int]$ImportPageNumber = 0,
    [int]$PageSize = 0,
    $Schema
)

BEGIN
{
    # Initialize variables for paged import
    $global:MoreToImport = $false
    $global:PageToken = $null
    
    # Get credentials
    if (-not $Credentials) {
        $Credentials = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))
    }
}

PROCESS
{
    try
    {
        # Query Active Directory for Computer objects
        $adSearcher = New-Object System.DirectoryServices.DirectorySearcher
        $adSearcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry "LDAP://", $Credentials.UserName, $Credentials.GetNetworkCredential().Password
        
        # Set filter to find computer objects
        $adSearcher.Filter = "(&(objectClass=computer))"
        
        # Define properties to retrieve
        $adSearcher.PropertiesToLoad.AddRange(@("sAMAccountName", "displayName", "extensionAttribute1"))
        
        # Set paging if applicable
        if ($UsePagedImport -and $PageSize -gt 0) {
            $adSearcher.PageSize = $PageSize
        }
        
        # Execute search
        $searchResults = $adSearcher.FindAll()
        
        # Process results
        $deviceCount = 0
        foreach ($result in $searchResults)
        {
            $properties = $result.Properties
            
            # Extract values
            $sAMAccountName = $properties["sAMAccountName"][0]
            $displayName = if ($properties["displayName"].Count -gt 0) { $properties["displayName"][0] } else { $null }
            $extensionAttribute1 = if ($properties["extensionAttribute1"].Count -gt 0) { $properties["extensionAttribute1"][0] } else { $null }
            
            # Skip if sAMAccountName is empty (use as anchor)
            if ([string]::IsNullOrEmpty($sAMAccountName)) {
                continue
            }
            
            # Create hashtable object for import
            $obj = @{}
            $obj.Add("Id", $sAMAccountName)
            $obj.Add("[ObjectClass]", "device")
            $obj.Add("[DN]", $result.Path -replace "LDAP://", "")
            $obj.Add("sAMAccountName", $sAMAccountName)
            
            # Add displayName if present
            if (-not [string]::IsNullOrEmpty($displayName)) {
                $obj.Add("displayName", $displayName)
            }
            
            # Add extensionAttribute1 if present
            if (-not [string]::IsNullOrEmpty($extensionAttribute1)) {
                $obj.Add("extensionAttribute1", $extensionAttribute1)
            }
            
            # Add success status
            $obj.Add("[ErrorName]", "success")
            
            # Return object to pipeline
            $obj
            
            $deviceCount++
        }
    }
    catch
    {
        # Create error object
        $errorObj = @{}
        $errorObj.Add("Id", "ERROR")
        $errorObj.Add("[ObjectClass]", "device")
        $errorObj.Add("[ErrorName]", "import-error")
        $errorObj.Add("[ErrorDetail]", $_.Exception.Message)
        
        $errorObj
    }
}

END
{
    # For delta imports, save watermark
    if ($OperationType -eq 'Delta') {
        $global:RunStepCustomData = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}
