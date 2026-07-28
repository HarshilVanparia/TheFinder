<#
.SYNOPSIS
    Interactive actions module.
.DESCRIPTION
    Handles commands entered by the user during or after the search process,
    such as opening files, navigating to their containing folders, or copying paths.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-ItemAction {
    <#
    .SYNOPSIS
        Parses and executes a user command against a specific search result.
    .DESCRIPTION
        Supported commands:
        - open <id>: Opens the file or folder using the default system handler.
        - path <id>: Opens Windows Explorer and selects the target item.
        - copy <id>: Copies the full path to the clipboard.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Command,

        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )

    $Command = $Command.Trim()
    if ([string]::IsNullOrWhiteSpace($Command)) { return }

    # Split command into action and index (e.g., "open 15")
    $Parts = $Command -split '\s+', 2
    if ($Parts.Count -lt 2) {
        Write-Host "`nInvalid command. Format: <action> <id> (e.g., open 1, path 2, copy 3)" -ForegroundColor Red
        return
    }

    $Action = $Parts[0].ToLower()
    $IdString = $Parts[1]
    $Id = 0

    if (-not [int]::TryParse($IdString, [ref]$Id)) {
        Write-Host "`nInvalid ID. Must be a number." -ForegroundColor Red
        return
    }

    if (-not $Results.ContainsKey($Id)) {
        Write-Host "`nID [$Id] not found in the current results." -ForegroundColor Red
        return
    }

    $TargetItem = $Results[$Id]
    $TargetPath = $TargetItem.Path

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Host "`nThe item no longer exists at the specified path: $TargetPath" -ForegroundColor Red
        return
    }

    switch ($Action) {
        "open" {
            try {
                Write-Host "`nOpening: $TargetPath" -ForegroundColor Cyan
                Start-Process -FilePath $TargetPath -ErrorAction Stop
            }
            catch {
                Write-Host "`nFailed to open item: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "path" {
            try {
                Write-Host "`nOpening location for: $TargetPath" -ForegroundColor Cyan
                # Opens Explorer and highlights the specific file/folder
                Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$TargetPath`"" -ErrorAction Stop
            }
            catch {
                Write-Host "`nFailed to open path: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        "copy" {
            try {
                Set-Clipboard -Value $TargetPath -ErrorAction Stop
                Write-Host "`nCopied to clipboard: $TargetPath" -ForegroundColor Green
            }
            catch {
                Write-Host "`nFailed to copy to clipboard: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        default {
            Write-Host "`nUnknown action '$Action'. Supported actions: open, path, copy" -ForegroundColor Red
        }
    }
}

Export-ModuleMember -Function Invoke-ItemAction