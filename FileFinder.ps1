<#
.SYNOPSIS
    Standalone terminal-based Windows File Finder.
.DESCRIPTION
    All modules merged into a single portable file for ps2exe compilation.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Host.Name -notmatch 'Console') { Write-Warning "Run in standard console." }

# ==========================================
# MODULE: UTILS
# ==========================================
function Get-FileFinderConfig {
    param ([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        try {
            $JsonContent = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($JsonContent)) { return $JsonContent | ConvertFrom-Json }
        } catch { Write-Warning "Config unreadable. Generating new." }
    }
    return [PSCustomObject]@{ RecentSearches = @(); RecentExtensions = @(); LastSelectedDrives = @(); DefaultSearchScope = 3 }
}

function Save-FileFinderConfig {
    param ([psobject]$Config, [string]$Path)
    try { $Config | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Format-Size {
    param ([long]$Bytes)
    $KB = 1024; $MB = $KB * 1024; $GB = $MB * 1024; $TB = [long]$GB * 1024
    if ($Bytes -ge $TB) { return "{0:N2} TB" -f ($Bytes / $TB) }
    if ($Bytes -ge $GB) { return "{0:N2} GB" -f ($Bytes / $GB) }
    if ($Bytes -ge $MB) { return "{0:N2} MB" -f ($Bytes / $MB) }
    if ($Bytes -ge $KB) { return "{0:N2} KB" -f ($Bytes / $KB) }
    return "$Bytes B"
}

function Write-ConsoleProgress {
    param ([psobject]$Progress)
    $CurrentDir = $Progress.CurrentDirectory
    if (-not [string]::IsNullOrEmpty($CurrentDir) -and $CurrentDir.Length -gt 70) { $CurrentDir = "..." + $CurrentDir.Substring($CurrentDir.Length - 67) } 
    elseif ([string]::IsNullOrEmpty($CurrentDir)) { $CurrentDir = "Initializing..." }
    $Status = "Drive: $($Progress.CurrentDrive) | Scanned: $($Progress.Scanned.ToString('N0')) | Found: $($Progress.Found.ToString('N0')) | Time: $($Progress.Elapsed)"
    Write-Progress -Activity "File Finder Search in Progress" -Status $Status -CurrentOperation $CurrentDir -PercentComplete -1
}

function Clear-ConsoleProgress { Write-Progress -Activity "File Finder Search in Progress" -Completed }

# ==========================================
# MODULE: DRIVES
# ==========================================
function Get-AvailableDrives {
    try { return @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | Select-Object -ExpandProperty Name) } catch { return @() }
}

function Prompt-DriveSelection {
    param ([psobject]$Config)
    $ReadyDrives = Get-AvailableDrives
    if ($ReadyDrives.Count -eq 0) { Write-Error "No ready drives found."; exit }

    $Scope = 0
    while ($Scope -notin @(1, 2, 3)) {
        Write-Host "`nSelect search location." -ForegroundColor Cyan
        Write-Host "1 Single drive`n2 Multiple drives`n3 Entire system" -ForegroundColor Yellow
        $DefaultHint = if ($Config.DefaultSearchScope) { " [Default: $($Config.DefaultSearchScope)]" } else { "" }
        $ScopeInput = Read-Host "`nEnter option (1-3)$DefaultHint"
        
        if ([string]::IsNullOrWhiteSpace($ScopeInput) -and $Config.DefaultSearchScope) { $Scope = [int]$Config.DefaultSearchScope }
        elseif ([int]::TryParse($ScopeInput, [ref]$Scope) -and $Scope -in @(1, 2, 3)) { $Config.DefaultSearchScope = $Scope }
    }

    if ($Scope -eq 3) { $SelectedDrives = $ReadyDrives }
    else {
        $DriveLetters = @($ReadyDrives | ForEach-Object { $_.Substring(0, 1).ToUpper() })
        Write-Host "`nAvailable drives: $($DriveLetters -join ', ')" -ForegroundColor Cyan
        $ValidSelection = $false
        while (-not $ValidSelection) {
            $PromptMsg = if ($Scope -eq 1) { "Enter drive letter (e.g., C)" } else { "Enter drive letters separated by commas (e.g., C,D,E)" }
            $DriveInput = Read-Host "`n$PromptMsg"
            if ([string]::IsNullOrWhiteSpace($DriveInput)) { continue }

            $InputDrives = @($DriveInput -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -ne '' })
            if ($Scope -eq 1 -and $InputDrives.Count -gt 1) { Write-Host "Please enter only one." -ForegroundColor Red; continue }

            $InvalidDrives = @($InputDrives | Where-Object { $_ -notin $DriveLetters })
            if ($InvalidDrives.Count -gt 0) { Write-Host "Invalid drive(s): $($InvalidDrives -join ', ')" -ForegroundColor Red; continue }

            $ValidSelection = $true
            $SelectedDrives = @($InputDrives | ForEach-Object { "$_`:\" })
        }
    }
    $Config.LastSelectedDrives = $SelectedDrives
    Write-Host "`nSelected Drives: " -ForegroundColor Cyan -NoNewline; Write-Host ($SelectedDrives -join ', ') -ForegroundColor Green
    return $SelectedDrives
}

# ==========================================
# MODULE: EXTENSIONS
# ==========================================
function Prompt-ExtensionFilter {
    param ([psobject]$Config)
    Write-Host "`nEnter extension filter (e.g., .exe). Leave empty for all." -ForegroundColor Cyan
    $RecentHint = ""
    $SafeRecentExts = @( $Config.RecentExtensions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } )
    if ($SafeRecentExts.Count -gt 0) { $RecentHint = " (Recent: $($SafeRecentExts[0]))" }

    $ExtInput = Read-Host "Extension$RecentHint"
    $FinalExtension = ""
    if (-not [string]::IsNullOrWhiteSpace($ExtInput)) {
        $FinalExtension = $ExtInput.Trim().ToLower()
        if (-not $FinalExtension.StartsWith(".")) { $FinalExtension = "." + $FinalExtension }
        $Config.RecentExtensions = @($FinalExtension) + @($SafeRecentExts | Where-Object { $_ -ne $FinalExtension }) | Select-Object -First 10
    }
    
    $DisplayExt = if ([string]::IsNullOrEmpty($FinalExtension)) { "All" } else { $FinalExtension }
    Write-Host "Selected Extension: " -ForegroundColor Cyan -NoNewline
    Write-Host $DisplayExt -ForegroundColor Green
    
    return $FinalExtension
}

# ==========================================
# MODULE: ACTIONS
# ==========================================
function Invoke-ItemAction {
    param ([string]$Command, [hashtable]$Results)
    $Command = $Command.Trim()
    if ([string]::IsNullOrWhiteSpace($Command)) { return }

    $Parts = $Command -split '\s+', 2
    if ($Parts.Count -lt 2) { Write-Host "`nInvalid command. Format: <action> <id> (e.g., open 1, path 2, copy 3)" -ForegroundColor Red; return }

    $Action = $Parts[0].ToLower(); $Id = 0
    if (-not [int]::TryParse($Parts[1], [ref]$Id) -or -not $Results.ContainsKey($Id)) { Write-Host "`nInvalid ID." -ForegroundColor Red; return }

    $TargetPath = $Results[$Id].Path
    if (-not (Test-Path -LiteralPath $TargetPath)) { Write-Host "`nItem no longer exists." -ForegroundColor Red; return }

    switch ($Action) {
        "open" { try { Write-Host "`nOpening: $TargetPath" -ForegroundColor Cyan; Start-Process -FilePath $TargetPath -ErrorAction Stop } catch { Write-Host "Failed." -ForegroundColor Red } }
        "path" { try { Write-Host "`nRevealing: $TargetPath" -ForegroundColor Cyan; Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$TargetPath`"" -ErrorAction Stop } catch { Write-Host "Failed." -ForegroundColor Red } }
        "copy" { try { Set-Clipboard -Value $TargetPath -ErrorAction Stop; Write-Host "`nCopied to clipboard." -ForegroundColor Green } catch { Write-Host "Failed." -ForegroundColor Red } }
        default { Write-Host "`nUnknown action '$Action'. Use: open, path, copy" -ForegroundColor Red }
    }
}

# ==========================================
# MODULE: SEARCH ENGINE
# ==========================================
function Start-AsyncSearch {
    param ([string[]]$Drives, [string]$SearchName, [int]$TargetType, [int]$SearchMode, [string]$Extension, $ResultQueue, $ProgressQueue, $CancellationToken)
    $ScriptBlock = {
        param ($Drives, $SearchName, $TargetType, $SearchMode, $Extension, $ResultQueue, $ProgressQueue, $CancellationToken)
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew(); $Scanned = 0; $Found = 0; $LastTime = $Stopwatch.ElapsedMilliseconds
        $Wildcard = $null; $SmartRegex = $null

        if ($SearchMode -eq 4) { $Wildcard = [System.Management.Automation.WildcardPattern]::new($SearchName, [System.Management.Automation.WildcardOptions]::Compiled -bor [System.Management.Automation.WildcardOptions]::IgnoreCase) } 
        elseif ($SearchMode -eq 1) { $SmartRegex = [regex]::new("(^|[^a-zA-Z0-9])$([regex]::Escape($SearchName))", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }

        foreach ($Drive in $Drives) {
            if ($CancellationToken.IsCancellationRequested) { break }
            $Stack = [System.Collections.Generic.Stack[string]]::new(); $Stack.Push($Drive)

            while ($Stack.Count -gt 0) {
                if ($CancellationToken.IsCancellationRequested) { break }
                $CurrentDir = $Stack.Pop()

                if (($Stopwatch.ElapsedMilliseconds - $LastTime) -gt 100) {
                    $ProgressQueue.Enqueue([PSCustomObject]@{ CurrentDrive = $Drive; Scanned = $Scanned; Found = $Found; Elapsed = $Stopwatch.Elapsed.ToString('hh\:mm\:ss'); CurrentDirectory = $CurrentDir })
                    $LastTime = $Stopwatch.ElapsedMilliseconds
                }

                try {
                    $Enumerator = [System.IO.DirectoryInfo]::new($CurrentDir).EnumerateFileSystemInfos().GetEnumerator()
                    while ($true) {
                        if ($CancellationToken.IsCancellationRequested) { break }
                        try { if (-not $Enumerator.MoveNext()) { break }; $Fsi = $Enumerator.Current } catch { continue }

                        $Scanned++
                        $IsFolder = ($Fsi.Attributes -band [System.IO.FileAttributes]::Directory) -eq [System.IO.FileAttributes]::Directory
                        if ($IsFolder) { $Stack.Push($Fsi.FullName) }

                        if ($TargetType -eq 1 -and $IsFolder) { continue }
                        if ($TargetType -eq 2 -and -not $IsFolder) { continue }
                        if (-not $IsFolder -and -not [string]::IsNullOrEmpty($Extension) -and $Fsi.Extension.ToLower() -ne $Extension) { continue }

                        $IsMatch = $false
                        if ($SearchMode -eq 4) { $IsMatch = $Wildcard.IsMatch($Fsi.Name) } 
                        elseif ($SearchMode -eq 1) { $IsMatch = $SmartRegex.IsMatch($Fsi.Name) } 
                        elseif ($SearchMode -eq 2) { $IsMatch = $Fsi.Name.IndexOf($SearchName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } 
                        elseif ($SearchMode -eq 3) {
                            $IsMatch = [string]::Equals($Fsi.Name, $SearchName, [System.StringComparison]::OrdinalIgnoreCase)
                            if (-not $IsFolder -and -not $IsMatch) { $IsMatch = [string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($Fsi.Name), $SearchName, [System.StringComparison]::OrdinalIgnoreCase) }
                        }

                        if ($IsMatch) {
                            $Found++
                            $ResultQueue.Enqueue([PSCustomObject]@{ Name = $Fsi.Name; Path = $Fsi.FullName; Size = if ($IsFolder) { 0 } else { $Fsi.Length }; Modified = $Fsi.LastWriteTime.ToString('yyyy-MM-dd HH:mm'); IsFolder = $IsFolder })
                        }
                    }
                } catch { continue }
            }
        }
        $ProgressQueue.Enqueue([PSCustomObject]@{ CurrentDrive = "Completed"; Scanned = $Scanned; Found = $Found; Elapsed = $Stopwatch.Elapsed.ToString('hh\:mm\:ss'); CurrentDirectory = "" })
        $Stopwatch.Stop()
    }
    $PowerShell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($Drives).AddArgument($SearchName).AddArgument($TargetType).AddArgument($SearchMode).AddArgument($Extension).AddArgument($ResultQueue).AddArgument($ProgressQueue).AddArgument($CancellationToken)
    return [PSCustomObject]@{ PowerShell = $PowerShell; AsyncResult = $PowerShell.BeginInvoke() }
}
function Stop-AsyncSearch { param ($Job) try { if ($null -ne $Job.PowerShell) { $Job.PowerShell.Stop(); $Job.PowerShell.Dispose() } } catch { } }

# ==========================================
# MAIN EXECUTION
# ==========================================
$CancellationToken = $null; $RunspaceJob = $null

try {
    if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') { $BasePath = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    else { $BasePath = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    $ConfigPath = Join-Path $BasePath "config.json"

    if (-not (Test-Path $ConfigPath)) {
        @{ RecentSearches = @(); RecentExtensions = @(); LastSelectedDrives = @(); DefaultSearchScope = 3 } | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigPath -Encoding UTF8
    }
    $Config = Get-FileFinderConfig -Path $ConfigPath

    [Console]::Clear()
    Write-Host "=== Windows Terminal File Finder ===" -ForegroundColor Cyan
    
    $SelectedDrives = Prompt-DriveSelection -Config $Config
    
    $SearchName = Read-Host "`nEnter search name (wildcards supported)"
    if ([string]::IsNullOrWhiteSpace($SearchName)) { exit }
    
    if (-not $Config.RecentSearches) { $Config.RecentSearches = @() }
    $Config.RecentSearches = @($SearchName) + @($Config.RecentSearches | Where-Object { $_ -ne $SearchName }) | Select-Object -First 10

    $TargetType = 0
    while ($TargetType -notin @(1, 2, 3)) {
        Write-Host "`nTarget Type: 1=Files 2=Folders 3=Both" -ForegroundColor Cyan
        $TypeInput = Read-Host "Enter option (1-3) [Default: 3]"
        if ([string]::IsNullOrWhiteSpace($TypeInput)) { $TargetType = 3 }
        elseif ([int]::TryParse($TypeInput, [ref]$TargetType) -and $TargetType -in @(1, 2, 3)) { }
    }

    $SearchMode = 1
    $HasWildcard = ($SearchName.Contains('*') -or $SearchName.Contains('?'))
    if (-not $HasWildcard) {
        $SearchMode = 0
        while ($SearchMode -notin @(1, 2, 3)) {
            Write-Host "`nMatch Mode: 1=Smart 2=Partial 3=Exact" -ForegroundColor Cyan
            $ModeInput = Read-Host "Enter option (1-3) [Default: 1]"
            if ([string]::IsNullOrWhiteSpace($ModeInput)) { $SearchMode = 1 }
            elseif ([int]::TryParse($ModeInput, [ref]$SearchMode) -and $SearchMode -in @(1, 2, 3)) { }
        }
    } else { $SearchMode = 4 }

    $Extension = ""
    if ($TargetType -ne 2) { $Extension = Prompt-ExtensionFilter -Config $Config }

    Save-FileFinderConfig -Config $Config -Path $ConfigPath

    Write-Host "`nStarting search. Type 'open <id>', 'path <id>', or 'copy <id>' at any time." -ForegroundColor Green
    Write-Host "Press Ctrl+C to cancel.`n" -ForegroundColor DarkGray

    $ResultQueue = [System.Collections.Concurrent.ConcurrentQueue[psobject]]::new()
    $ProgressQueue = [System.Collections.Concurrent.ConcurrentQueue[psobject]]::new()
    $CancellationToken = [System.Threading.CancellationTokenSource]::new()

    $RunspaceJob = Start-AsyncSearch -Drives $SelectedDrives -SearchName $SearchName -TargetType $TargetType -SearchMode $SearchMode -Extension $Extension -ResultQueue $ResultQueue -ProgressQueue $ProgressQueue -CancellationToken $CancellationToken.Token

    $Results = @{}
    $ResultIndex = 1
    $CommandBuffer = ""
    $SearchDone = $false
    [Console]::TreatControlCAsInput = $true

    function Clear-InputLine { [Console]::Write("`r$([string]::new(' ', [Console]::WindowWidth - 1))`r") }
    function Draw-InputLine { [Console]::Write("`rPS> $CommandBuffer") }

    Draw-InputLine

    while ($true) {
        $HasOutput = $false; $NeedsRedraw = $false

        $ResultItem = $null
        while ($ResultQueue.TryDequeue([ref]$ResultItem)) {
            $HasOutput = $true; $Results[$ResultIndex] = $ResultItem
            $SizeStr = if ($ResultItem.IsFolder) { "Folder" } else { Format-Size -Bytes $ResultItem.Size }

            Clear-InputLine
            Write-Host @"
--------------------------------------------------
[$ResultIndex]
Name     : $($ResultItem.Name)
Path     : $($ResultItem.Path)
Size     : $SizeStr
Modified : $($ResultItem.Modified)
"@ -ForegroundColor Yellow
            $ResultIndex++; $NeedsRedraw = $true
        }

        $ProgressItem = $null; $LatestProgress = $null
        while ($ProgressQueue.TryDequeue([ref]$ProgressItem)) { $LatestProgress = $ProgressItem }
        if ($null -ne $LatestProgress) { Write-ConsoleProgress -Progress $LatestProgress }

        $IsCompleted = ($RunspaceJob.PowerShell.InvocationStateInfo.State -in 'Completed', 'Failed')
        if ($IsCompleted -and $ResultQueue.IsEmpty -and $ProgressQueue.IsEmpty -and -not $SearchDone) {
            $SearchDone = $true; Clear-ConsoleProgress; Clear-InputLine
            Write-Host "`nSearch complete. Type a command or press ENTER to exit." -ForegroundColor Cyan
            $NeedsRedraw = $true
        }

        if ([Console]::KeyAvailable) {
            $Key = [Console]::ReadKey($true)
            if ($Key.Key -eq [System.ConsoleKey]::C -and $Key.Modifiers -match 'Control') { Clear-InputLine; Write-Host "Cancelling..." -ForegroundColor Red; break }
            elseif ($Key.Key -eq [System.ConsoleKey]::Enter) {
                Clear-InputLine
                if (-not [string]::IsNullOrWhiteSpace($CommandBuffer)) { Invoke-ItemAction -Command $CommandBuffer -Results $Results } 
                elseif ($SearchDone) { break }
                $CommandBuffer = ""; $NeedsRedraw = $true
            } 
            elseif ($Key.Key -eq [System.ConsoleKey]::Backspace) {
                if ($CommandBuffer.Length -gt 0) { $CommandBuffer = $CommandBuffer.Substring(0, $CommandBuffer.Length - 1); Clear-InputLine; $NeedsRedraw = $true }
            } 
            elseif ($Key.Key -eq [System.ConsoleKey]::Escape) { $CommandBuffer = ""; Clear-InputLine; $NeedsRedraw = $true } 
            elseif (-not [char]::IsControl($Key.KeyChar)) { $CommandBuffer += $Key.KeyChar; [Console]::Write($Key.KeyChar) }
        }

        if ($NeedsRedraw) { Draw-InputLine }
        if ($IsCompleted -and $ResultQueue.IsEmpty) { Start-Sleep -Milliseconds 50 } 
        elseif (-not $HasOutput) { Start-Sleep -Milliseconds 20 }
    }
} catch { 
    Write-Error "An unexpected error occurred: $($_.Exception.Message)"
    Write-Host "`nPress Enter to exit..." -ForegroundColor Red; Read-Host
} finally {
    [Console]::TreatControlCAsInput = $false
    if ($null -ne $CancellationToken) { $CancellationToken.Cancel(); $CancellationToken.Dispose() }
    if ($null -ne $RunspaceJob) { Stop-AsyncSearch -Job $RunspaceJob }
    Clear-ConsoleProgress
}