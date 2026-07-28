<#
.SYNOPSIS
    Utility functions for the File Finder application.
.DESCRIPTION
    Handles configuration loading/saving, data formatting, and non-blocking progress UI.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FileFinderConfig {
    <#
    .SYNOPSIS
        Loads the application configuration from a JSON file.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            $JsonContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($JsonContent)) {
                return $JsonContent | ConvertFrom-Json
            }
        }
        catch {
            Write-Warning "Failed to read configuration file. A new one will be generated."
        }
    }
    
    # Return default config structure if file is missing or corrupt
    return [PSCustomObject]@{
        RecentSearches     = @()
        RecentExtensions   = @()
        LastSelectedDrives = @()
        DefaultSearchScope = 3
    }
}

function Save-FileFinderConfig {
    <#
    .SYNOPSIS
        Saves the application configuration to a JSON file.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$Config,

        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    try {
        $Config | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to save configuration to $Path."
    }
}

function Format-Size {
    <#
    .SYNOPSIS
        Converts bytes into a human-readable file size string.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [long]$Bytes
    )

    $KB = 1024
    $MB = $KB * 1024
    $GB = $MB * 1024
    $TB = [long]$GB * 1024

    if ($Bytes -ge $TB) { return "{0:N2} TB" -f ($Bytes / $TB) }
    if ($Bytes -ge $GB) { return "{0:N2} GB" -f ($Bytes / $GB) }
    if ($Bytes -ge $MB) { return "{0:N2} MB" -f ($Bytes / $MB) }
    if ($Bytes -ge $KB) { return "{0:N2} KB" -f ($Bytes / $KB) }
    return "$Bytes B"
}

function Write-ConsoleProgress {
    <#
    .SYNOPSIS
        Displays the current search progress using the native PowerShell progress bar.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$Progress
    )

    $Activity = "File Finder Search in Progress"
    $Status = "Drive: $($Progress.CurrentDrive) | Scanned: $($Progress.Scanned.ToString('N0')) | Found: $($Progress.Found.ToString('N0')) | Time: $($Progress.Elapsed)"
    
    # Safely truncate directory path if it's too long to prevent console wrapping artifacts
    $CurrentDir = $Progress.CurrentDirectory
    if (-not [string]::IsNullOrEmpty($CurrentDir) -and $CurrentDir.Length -gt 70) {
        $CurrentDir = "..." + $CurrentDir.Substring($CurrentDir.Length - 67)
    } elseif ([string]::IsNullOrEmpty($CurrentDir)) {
        $CurrentDir = "Initializing..."
    }
    
    Write-Progress -Activity $Activity -Status $Status -CurrentOperation $CurrentDir -PercentComplete -1
}

function Clear-ConsoleProgress {
    <#
    .SYNOPSIS
        Clears the active progress bar from the console.
    #>
    Write-Progress -Activity "File Finder Search in Progress" -Completed
}

Export-ModuleMember -Function Get-FileFinderConfig, Save-FileFinderConfig, Format-Size, Write-ConsoleProgress, Clear-ConsoleProgress