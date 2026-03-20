#Requires -Version 5.1
<#
.SYNOPSIS
    Export les membres d'un Set MIM avec analyse des dates de fin de contrat
    
.DESCRIPTION
    Ce script exporte tous les membres d'un Set MIM spécifié et analyse:
    - Les dates de fin de contrat (EmployeeEndDate)
    - L'état des comptes (UserState)
    - Les dates de désactivation et suppression
    
.PARAMETER SetDisplayName
    Nom d'affichage du Set MIM à exporter
    
.PARAMETER OutputPath
    Chemin du fichier CSV de sortie (optionnel)
    
.EXAMPLE
    .\Exportuserfromset.ps1 -SetDisplayName "All Employees"
    
.NOTES
    Auteur: Jean-Baptiste DUMAY
    Date: 2025
    Environnement: Limagrain MIM
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SetDisplayName,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

# Configuration
$ErrorActionPreference = 'Stop'

# Fonction pour écrire les logs
function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor White }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
}


# Fonction pour récupérer les membres du Set
function Get-SetMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetDisplayName
    )
    
    try {
        Write-LogMessage "Récupération des membres du Set '$SetDisplayName'..."
        
        # XPath pour récupérer tous les objets Person membres du Set
        $xpath = "/Person[ObjectID=/Set[DisplayName='$SetDisplayName']/ComputedMember]"
        
        # Attributs à récupérer
        $attributesToGet = @(
            "EmployeeID",
            "EmployeeStartDate",
            "EmployeeEndDate",
            "DisplayName",
            "AccountName",
            "Domain",
            "ObjectID",
            "EmployeeType",
            "JobTitle"
        )
        
        $members = Search-Resources -Xpath $xpath -AttributesToGet $attributesToGet
        
        if ($null -eq $members -or $members.Count -eq 0) {
            Write-LogMessage "Aucun membre trouvé dans le Set" -Level Warning
            return @()
        }
        
        Write-LogMessage "Nombre de membres trouvés : $($members.Count)" -Level Success
        return $members
    }
    catch {
        Write-LogMessage "Erreur lors de la récupération des membres: $($_.Exception.Message)" -Level Error
        throw
    }
}

# Fonction pour analyser et exporter les données
function Export-UsersAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Members,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        Write-LogMessage "Export des $($Members.Count) membres..."
        
        # Récupérer TOUS les utilisateurs AD en une seule requête
        Write-LogMessage "Récupération des données AD (une seule requête)..."
        $adUsers = @{}
        try {
            $allAdUsers = Get-ADUser -Filter * -Properties LastLogonDate, LastLogonTimeStamp, Description -ErrorAction SilentlyContinue
            foreach ($user in $allAdUsers) {
                $adUsers[$user.SamAccountName] = $user
            }
            Write-LogMessage "Données AD récupérées pour $($adUsers.Count) utilisateurs" -Level Success
        }
        catch {
            Write-LogMessage "Erreur lors de la récupération des utilisateurs AD: $($_.Exception.Message)" -Level Warning
        }
        
        $exportData = @()
        $counter = 0
        
        foreach ($member in $Members) {
            $counter++
            $percentComplete = [math]::Round(($counter / $Members.Count) * 100, 2)
            
            # Afficher la barre de progression
            Write-Progress -Activity "Analyse des membres du Set" `
                          -Status "Traitement de $counter sur $($Members.Count) ($percentComplete%)" `
                          -PercentComplete $percentComplete `
                          -CurrentOperation "Analyse de l'utilisateur : $($member.AccountName)"
            
            # Extraction des valeurs
            $employeeID = if ($member.EmployeeID) { $member.EmployeeID } else { "N/A" }
            $displayName = if ($member.DisplayName) { $member.DisplayName } else { "N/A" }
            $accountName = if ($member.AccountName) { $member.AccountName } else { "N/A" }
            $domain = if ($member.Domain) { $member.Domain } else { "N/A" }
            $startDate = if ($member.EmployeeStartDate) { $member.EmployeeStartDate } else { $null }
            $endDate = if ($member.EmployeeEndDate) { $member.EmployeeEndDate } else { $null }
            $employeeType = if ($member.EmployeeType) { $member.EmployeeType } else { "N/A" }
            $jobTitle = if ($member.JobTitle) { $member.JobTitle } else { "N/A" }
            
            # Récupération du LastLogonAD et Description depuis le cache
            $lastLogonAD = $null
            $descriptionAD = "N/A"
            
            if ($accountName -ne "N/A" -and $adUsers.ContainsKey($accountName)) {
                $adUser = $adUsers[$accountName]
                
                # Récupérer les deux dates de dernière connexion
                $lastLogonDate = $adUser.LastLogonDate
                $lastLogonTimeStamp = $null
                
                # Convertir LastLogonTimeStamp si présent
                if ($adUser.LastLogonTimeStamp) {
                    $lastLogonTimeStamp = [DateTime]::FromFileTime($adUser.LastLogonTimeStamp)
                }
                
                # Déterminer la date la plus récente
                if ($lastLogonDate -and $lastLogonTimeStamp) {
                    $lastLogonAD = if ($lastLogonDate -gt $lastLogonTimeStamp) { $lastLogonDate } else { $lastLogonTimeStamp }
                }
                elseif ($lastLogonDate) {
                    $lastLogonAD = $lastLogonDate
                }
                elseif ($lastLogonTimeStamp) {
                    $lastLogonAD = $lastLogonTimeStamp
                }
                
                $descriptionAD = if ($adUser.Description) { $adUser.Description } else { "N/A" }
            }
            
            # Créer l'objet pour l'export
            $userInfo = [PSCustomObject]@{
                ObjectID = $member.ObjectID
                EmployeeID = $employeeID
                DisplayName = $displayName
                AccountName = $accountName
                Domain = $domain
                EmployeeType = $employeeType
                JobTitle = $jobTitle
                Description = $descriptionAD
                EmployeeStartDate = if ($startDate) { $startDate.ToString("yyyy-MM-dd") } else { "N/A" }
                EmployeeEndDate = if ($endDate) { $endDate.ToString("yyyy-MM-dd") } else { "N/A" }
                LastLogonAD = if ($lastLogonAD) { $lastLogonAD.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
            }
            
            $exportData += $userInfo
        }
        
        # Fermer la barre de progression
        Write-Progress -Activity "Analyse des membres du Set" -Completed
        
        # Export vers CSV
        $exportData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter ";"
        Write-LogMessage "Export réussi : $OutputPath" -Level Success
        Write-LogMessage "Nombre total d'utilisateurs : $($exportData.Count)" -Level Info
        
        # Génération de l'export Excel
        $excelPath = $OutputPath -replace ".csv$", ".xlsx"
        Export-ToExcel -ExportData $exportData -ExcelPath $excelPath
    }
    catch {
        Write-LogMessage "Erreur lors de l'export des données: $($_.Exception.Message)" -Level Error
        throw
    }
}

# Fonction pour générer l'export Excel avec formatage conditionnel
function Export-ToExcel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$ExportData,
        
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath
    )
    
    try {
        Write-LogMessage "Génération de l'export Excel..." -Level Info
        
        # Vérifier si le module ImportExcel est disponible
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Write-LogMessage "Module ImportExcel non disponible. Installation en cours..." -Level Warning
            Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
            Write-LogMessage "Module ImportExcel installé avec succès" -Level Success
        }
        
        Import-Module ImportExcel -ErrorAction Stop
        
        # Export direct vers Excel avec style de base
        $excelParams = @{
            Path = $ExcelPath
            AutoSize = $true
            AutoFilter = $true
            FreezeTopRow = $true
            TableName = "UsersExport"
            WorksheetName = "Export Utilisateurs"
            ClearSheet = $true
            TableStyle = "Medium2"
        }
        
        Write-LogMessage "Export des données vers Excel..." -Level Info
        $ExportData | Export-Excel @excelParams
        
        Write-LogMessage "Export Excel réussi : $ExcelPath" -Level Success
    }
    catch {
        Write-LogMessage "Erreur lors de l'export Excel: $($_.Exception.Message)" -Level Error
        Write-LogMessage "L'export CSV reste disponible" -Level Info
    }
}

# Fonction principale
function Main {
    [CmdletBinding()]
    param()
    
    try {
        $startTime = Get-Date
        Write-LogMessage "=== DÉBUT DE L'EXPORT DES UTILISATEURS DU SET ===" -Level Success
        
        # Configuration du chemin de sortie
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $OutputPath = Join-Path $PSScriptRoot "SetMembers_Export_$timestamp.csv"
        }
        
        # Récupération des membres directement
        $members = Get-SetMembers -SetDisplayName $SetDisplayName
        
        if ($members.Count -eq 0) {
            Write-LogMessage "Aucun membre à exporter. Arrêt du script." -Level Warning
            return
        }
        
        # Export et analyse
        Export-UsersAnalysis -Members $members -OutputPath $OutputPath
        
        $endTime = Get-Date
        $duration = $endTime - $startTime
        Write-LogMessage "=== EXPORT TERMINÉ AVEC SUCCÈS ===" -Level Success
        Write-LogMessage "Durée totale: $($duration.ToString('hh\:mm\:ss'))" -Level Success
    }
    catch {
        Write-LogMessage "Erreur critique lors de l'exécution: $($_.Exception.Message)" -Level Error
        Write-LogMessage "Stack trace: $($_.ScriptStackTrace)" -Level Error
        throw
    }
}

# Point d'entrée du script
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
