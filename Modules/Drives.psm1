<#
.SYNOPSIS
    Drive detection and selection module.
.DESCRIPTION
    Discovers active, ready drives on the system and handles the interactive selection menus
    for single, multiple, or full system searches.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-AvailableDrives {
    <#
    .SYNOPSIS
        Retrieves a list of all currently available and ready drives.
    #>
    try {
        $Drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
        return @($Drives | Select-Object -ExpandProperty Name)
    }
    catch {
        Write-Warning "Could not enumerate drives: $($_.Exception.Message)"
        return @()
    }
}

function Prompt-DriveSelection {
    <#
    .SYNOPSIS
        Interactively prompts the user to select the search scope.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$Config
    )

    $ReadyDrives = Get-AvailableDrives
    if ($ReadyDrives.Count -eq 0) {
        Write-Error "No ready, accessible drives found on this system. Exiting."
        exit
    }

    $Scope = 0
    while ($Scope -notin @(1, 2, 3)) {
        Write-Host "`nSelect search location." -ForegroundColor Cyan
        Write-Host "Options" -ForegroundColor DarkGray
        Write-Host "1" -ForegroundColor Yellow -NoNewline; Write-Host " Single drive"
        Write-Host "2" -ForegroundColor Yellow -NoNewline; Write-Host " Multiple drives"
        Write-Host "3" -ForegroundColor Yellow -NoNewline; Write-Host " Entire system"
        
        $DefaultHint = if ($Config.DefaultSearchScope) { " [Default: $($Config.DefaultSearchScope)]" } else { "" }
        $ScopeInput = Read-Host "`nEnter option (1-3)$DefaultHint"
        
        if ([string]::IsNullOrWhiteSpace($ScopeInput) -and $Config.DefaultSearchScope) {
            $Scope = [int]$Config.DefaultSearchScope
        }
        elseif ([int]::TryParse($ScopeInput, [ref]$Scope) -and $Scope -in @(1, 2, 3)) {
            $Config.DefaultSearchScope = $Scope
        }
        else {
            Write-Host "Invalid option. Please enter 1, 2, or 3." -ForegroundColor Red
        }
    }

    $SelectedDrives = @()

    if ($Scope -eq 3) {
        $SelectedDrives = $ReadyDrives
    }
    else {
        # Extract just the drive letter (e.g., C:\ becomes C) for clean matching
        $DriveLetters = @($ReadyDrives | ForEach-Object { $_.Substring(0, 1).ToUpper() })
        
        Write-Host "`nAvailable drives:" -ForegroundColor Cyan
        $DriveLetters | ForEach-Object { Write-Host $_ }
        
        $ValidSelection = $false
        while (-not $ValidSelection) {
            if ($Scope -eq 1) {
                $PromptMsg = "Enter drive letter (e.g., C)"
            } else {
                $PromptMsg = "Enter drive letters separated by commas (e.g., C,D,E)"
            }
            
            $DriveInput = Read-Host "`n$PromptMsg"
            
            if ([string]::IsNullOrWhiteSpace($DriveInput)) {
                Write-Host "Selection cannot be empty." -ForegroundColor Red
                continue
            }

            # Parse input, remove spaces, and convert to uppercase. Wrap in @() for StrictMode safety.
            $InputDrives = @($DriveInput -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -ne '' })
            
            if ($Scope -eq 1 -and $InputDrives.Count -gt 1) {
                Write-Host "Please enter only one drive letter." -ForegroundColor Red
                continue
            }

            $InvalidDrives = @($InputDrives | Where-Object { $_ -notin $DriveLetters })
            if ($InvalidDrives.Count -gt 0) {
                Write-Host "Invalid or unavailable drive(s) selected: $($InvalidDrives -join ', ')" -ForegroundColor Red
                continue
            }

            $ValidSelection = $true
            # Re-append the colon and backslash for the search engine (e.g., C -> C:\)
            $SelectedDrives = @($InputDrives | ForEach-Object { "$_`:\" })
        }
    }

    # Update configuration
    $Config.LastSelectedDrives = $SelectedDrives
    
    Write-Host "`nSelected Drives: " -ForegroundColor Cyan -NoNewline
    Write-Host ($SelectedDrives -join ', ') -ForegroundColor Green

    return $SelectedDrives
}

Export-ModuleMember -Function Get-AvailableDrives, Prompt-DriveSelection