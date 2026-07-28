<#
.SYNOPSIS
    Extension filter parsing module.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Prompt-ExtensionFilter {
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$Config
    )

    Write-Host "`nEnter extension filter." -ForegroundColor Cyan
    Write-Host "Examples: .exe, .pdf, .txt" -ForegroundColor DarkGray
    Write-Host "Leave empty to search all extensions." -ForegroundColor DarkGray
    
    $RecentHint = ""
    
    # Fully wrap the pipeline in @() so it always evaluates as an Array, even if only 1 item exists
    $SafeRecentExts = @( $Config.RecentExtensions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } )
    
    if ($SafeRecentExts.Count -gt 0) {
        $RecentHint = " (Recent: $($SafeRecentExts[0]))"
    }

    $ExtInput = Read-Host "`nExtension$RecentHint"

    $FinalExtension = ""

    if (-not [string]::IsNullOrWhiteSpace($ExtInput)) {
        $FinalExtension = $ExtInput.Trim().ToLower()
        
        if (-not $FinalExtension.StartsWith(".")) {
            $FinalExtension = "." + $FinalExtension
        }
        
        # Update recent extensions list safely
        $Config.RecentExtensions = @($FinalExtension) + @($SafeRecentExts | Where-Object { $_ -ne $FinalExtension }) | Select-Object -First 10
    }

    Write-Host "`nSelected Extension: " -ForegroundColor Cyan -NoNewline
    if ([string]::IsNullOrEmpty($FinalExtension)) {
        Write-Host "All" -ForegroundColor Green
    } else {
        Write-Host $FinalExtension -ForegroundColor Green
    }

    return $FinalExtension
}

Export-ModuleMember -Function Prompt-ExtensionFilter