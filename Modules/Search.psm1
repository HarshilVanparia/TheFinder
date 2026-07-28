<#
.SYNOPSIS
    Asynchronous search engine module.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Start-AsyncSearch {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$Drives,

        [Parameter(Mandatory=$true)]
        [string]$SearchName,

        [Parameter(Mandatory=$true)]
        [int]$TargetType,
        
        [Parameter(Mandatory=$true)]
        [int]$SearchMode,

        [Parameter(Mandatory=$false)]
        [string]$Extension,

        [Parameter(Mandatory=$true)]
        [System.Collections.Concurrent.ConcurrentQueue[psobject]]$ResultQueue,

        [Parameter(Mandatory=$true)]
        [System.Collections.Concurrent.ConcurrentQueue[psobject]]$ProgressQueue,

        [Parameter(Mandatory=$true)]
        [System.Threading.CancellationToken]$CancellationToken
    )

    $ScriptBlock = {
        param (
            [string[]]$Drives,
            [string]$SearchName,
            [int]$TargetType,
            [int]$SearchMode,
            [string]$Extension,
            [System.Collections.Concurrent.ConcurrentQueue[psobject]]$ResultQueue,
            [System.Collections.Concurrent.ConcurrentQueue[psobject]]$ProgressQueue,
            [System.Threading.CancellationToken]$CancellationToken
        )

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $Scanned = 0
        $Found = 0
        $LastProgressTime = $Stopwatch.ElapsedMilliseconds

        $Wildcard = $null
        $SmartRegex = $null

        if ($SearchMode -eq 4) {
            $Wildcard = [System.Management.Automation.WildcardPattern]::new($SearchName, [System.Management.Automation.WildcardOptions]::Compiled -bor [System.Management.Automation.WildcardOptions]::IgnoreCase)
        } elseif ($SearchMode -eq 1) {
            # Matches start of string or preceded by a non-alphanumeric character (space, dot, hyphen, underscore)
            $Escaped = [regex]::Escape($SearchName)
            $SmartRegex = [regex]::new("(^|[^a-zA-Z0-9])$Escaped", [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }

        foreach ($Drive in $Drives) {
            if ($CancellationToken.IsCancellationRequested) { break }

            $Stack = [System.Collections.Generic.Stack[string]]::new()
            $Stack.Push($Drive)

            while ($Stack.Count -gt 0) {
                if ($CancellationToken.IsCancellationRequested) { break }
                
                $CurrentDir = $Stack.Pop()

                if (($Stopwatch.ElapsedMilliseconds - $LastProgressTime) -gt 100) {
                    $ProgressQueue.Enqueue([PSCustomObject]@{
                        CurrentDrive     = $Drive
                        Scanned          = $Scanned
                        Found            = $Found
                        Elapsed          = $Stopwatch.Elapsed.ToString('hh\:mm\:ss')
                        CurrentDirectory = $CurrentDir
                    })
                    $LastProgressTime = $Stopwatch.ElapsedMilliseconds
                }

                try {
                    $DirInfo = [System.IO.DirectoryInfo]::new($CurrentDir)
                    $Enumerator = $DirInfo.EnumerateFileSystemInfos().GetEnumerator()

                    while ($true) {
                        if ($CancellationToken.IsCancellationRequested) { break }
                        
                        try {
                            if (-not $Enumerator.MoveNext()) { break }
                            $Fsi = $Enumerator.Current
                        }
                        catch { continue }

                        $Scanned++
                        $IsFolder = ($Fsi.Attributes -band [System.IO.FileAttributes]::Directory) -eq [System.IO.FileAttributes]::Directory

                        if ($IsFolder) { $Stack.Push($Fsi.FullName) }

                        if ($TargetType -eq 1 -and $IsFolder) { continue }
                        if ($TargetType -eq 2 -and -not $IsFolder) { continue }

                        if (-not $IsFolder -and -not [string]::IsNullOrEmpty($Extension)) {
                            if ($Fsi.Extension.ToLower() -ne $Extension) { continue }
                        }

                        $IsMatch = $false
                        if ($SearchMode -eq 4) {
                            $IsMatch = $Wildcard.IsMatch($Fsi.Name)
                        } elseif ($SearchMode -eq 1) {
                            $IsMatch = $SmartRegex.IsMatch($Fsi.Name)
                        } elseif ($SearchMode -eq 2) {
                            $IsMatch = $Fsi.Name.IndexOf($SearchName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                        } elseif ($SearchMode -eq 3) {
                            if ($IsFolder) {
                                $IsMatch = [string]::Equals($Fsi.Name, $SearchName, [System.StringComparison]::OrdinalIgnoreCase)
                            } else {
                                $IsMatch = [string]::Equals($Fsi.Name, $SearchName, [System.StringComparison]::OrdinalIgnoreCase) -or 
                                           [string]::Equals([System.IO.Path]::GetFileNameWithoutExtension($Fsi.Name), $SearchName, [System.StringComparison]::OrdinalIgnoreCase)
                            }
                        }

                        if ($IsMatch) {
                            $Found++
                            $ResultQueue.Enqueue([PSCustomObject]@{
                                Name     = $Fsi.Name
                                Path     = $Fsi.FullName
                                Size     = if ($IsFolder) { 0 } else { $Fsi.Length }
                                Modified = $Fsi.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                                IsFolder = $IsFolder
                            })
                        }
                    }
                }
                catch { continue }
            }
        }
        
        $ProgressQueue.Enqueue([PSCustomObject]@{
            CurrentDrive     = "Completed"
            Scanned          = $Scanned
            Found            = $Found
            Elapsed          = $Stopwatch.Elapsed.ToString('hh\:mm\:ss')
            CurrentDirectory = ""
        })
        $Stopwatch.Stop()
    }

    $PowerShell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($Drives).AddArgument($SearchName).AddArgument($TargetType).AddArgument($SearchMode).AddArgument($Extension).AddArgument($ResultQueue).AddArgument($ProgressQueue).AddArgument($CancellationToken)
    $AsyncResult = $PowerShell.BeginInvoke()

    return [PSCustomObject]@{
        PowerShell  = $PowerShell
        AsyncResult = $AsyncResult
    }
}

function Stop-AsyncSearch {
    param ( [Parameter(Mandatory=$true)] [psobject]$Job )
    try { if ($null -ne $Job.PowerShell) { $Job.PowerShell.Stop(); $Job.PowerShell.Dispose() } } catch { }
}

Export-ModuleMember -Function Start-AsyncSearch, Stop-AsyncSearch