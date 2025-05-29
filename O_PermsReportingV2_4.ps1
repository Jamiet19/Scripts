# Set the root folder path and CSV output file path
$script:inputdepth = $null
$inputDepth = $null
$rootFolder = "O:\Safety - Space and Defence Work"
$timestamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
$csvFile = "c:\temp\NTFSPermissionsO_$timestamp.CSV"
$errorReportFile = "c:\temp\NTFSPermissionsO_Errors_$timestamp.CSV"
$global:ErrorBag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
$global:ResultsBag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

# Ensure PowerShell 7 is installed - Required for parallel processing
function Ensure-PowerShell7 {

    [CmdletBinding()]
    param()

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue

    if ($pwsh) {
        Write-Host "PowerShell 7 is already installed at $($pwsh.Source)"
    } else {
        Write-Host "PowerShell 7 is not installed. Installing PowerShell 7..."

        # Download the latest PowerShell 7 MSI installer from GitHub
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $msi = $latest.assets | Where-Object { $_.name -match 'win-x64\.msi$' } | Select-Object -First 1

        if ($msi -and $msi.browser_download_url) {
            $installerPath = "$env:TEMP\PowerShell-7-latest.msi"
            Invoke-WebRequest -Uri $msi.browser_download_url -OutFile $installerPath

            Write-Host "Running installer. You may be prompted for administrator credentials."
            Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /qn" -Wait -Verb RunAs

            Write-Host "PowerShell 7 installation complete. You may need to restart your terminal."
        } else {
            Write-Error "Could not find the PowerShell 7 MSI download link."
        }
    }
}
Ensure-PowerShell7

# helper function to map a temporary drive for long paths
function Map-TempDriveForLongPath {
    param (
        [string]$LongPath
    )
    $parts = $LongPath -split '\\'
    $currentPath = $parts[0] + '\\'
    $driveLetter = ([char[]](67..90) | Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) })[0] + ':'
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $testPath = Join-Path $currentPath $parts[$i]
        try {
            Get-Item -Path $testPath -ErrorAction Stop | Out-Null
            $currentPath = $testPath
        } catch {
            break
        }
    }
    New-PSDrive -Name $driveLetter.TrimEnd(':') -PSProvider FileSystem -Root $currentPath -ErrorAction SilentlyContinue | Out-Null
    $remainingPath = ($LongPath -replace [regex]::Escape($currentPath), '').TrimStart('\')
    $mappedPath = Join-Path $driveLetter $remainingPath
    return @{ Drive = $driveLetter; Path = $mappedPath }
}

# Function to get the NTFS permissions for a folder and its subfolders recursively
function Get-NTFSPermissions {
    param (
        [string]$path,
        [int]$depth,
        [string]$ErrorPath
    )
    if ($null -eq $script:inputDepth) {
        $script:inputDepth = $depth
    }
    $folderDepth = $depth - $script:inputDepth
    try { # Adding this to try catch for error handling of long file names
        $folder = Get-Item -Path $path -ErrorAction Stop
        $acl = Get-Acl -Path $path -ErrorAction Stop
        $rules = $acl.Access | Select-Object -Property IdentityReference, FileSystemRights, AccessControlType, IsInherited

        foreach ($rule in $rules) {
            $properties = @{
                "Folder" = $folder.FullName
                "Depth" = $folderDepth
                "IdentityReference" = $rule.IdentityReference
                "FileSystemRights" = $rule.FileSystemRights
                "AccessControlType" = $rule.AccessControlType
                "IsInherited" = $rule.IsInherited
            }
            #New-Object -TypeName PSObject -Property $properties | Export-Csv -Path $csvFile -Append -NoTypeInformation
            $resultObj = New-Object -TypeName PSObject -Property $properties
            $global:ResultsBag.Add($resultObj)
        } 
    } catch { # were here if there was an error in the try section
        # Lets check if the error is due to a long path
        if ($_.Exception.Message -match "The specified path, file name, or both are too long") {
            $mapResult = Map-TempDriveForLongPath -LongPath $path
            if ($mapResult) {
                try {
                    Get-NTFSPermissions -path $mapResult.Path -depth $depth
                } catch {
                } finally {
                    Remove-PSDrive -Name $mapResult.Drive.TrimEnd(':') -Force -ErrorAction SilentlyContinue
                }
            }
        } else {
            Write-Warning "Failed to process $($path): $($_.Exception.Message)"
            # Log the error to a separate CSV report
            $errorProperties = @{
                "Path" = $path
                "Depth" = $folderDepth
                "ErrorMessage" = $_.Exception.Message
                "Time" = (Get-Date).ToString('s')
            }
            $errorObj = New-Object -TypeName PSObject -Property $errorProperties
            if (-not (Test-Path $errorReportFile)) {
                $errorObj | Export-Csv -Path $errorReportFile -NoTypeInformation
            } else {
                $errorObj | Export-Csv -Path $errorReportFile -Append -NoTypeInformation
            }
        }
    }

    # Multithreaded processing of subfolders for performance
    try {
        $subFolders = Get-ChildItem -Path $path -Directory -ErrorAction Stop
    } catch {
        Write-Warning "Failed to enumerate subfolders in $($path): $($_.Exception.Message)"
        # Log the error to a separate CSV report for subfolder enumeration errors
        $errorProperties = @{
            "Path" = $path
            "Depth" = $folderDepth
            "ErrorMessage" = $_.Exception.Message
            "Time" = (Get-Date).ToString('s')
        }
        $errorObj = New-Object -TypeName PSObject -Property $errorProperties
        if (-not (Test-Path $errorReportFile)) {
            $errorObj | Export-Csv -Path $errorReportFile -NoTypeInformation
        } else {
            $errorObj | Export-Csv -Path $errorReportFile -Append -NoTypeInformation
        }
        return
    }

    if ($subFolders.Count -gt 0) {
        $throttleLimit = 8 # Adjust based on your CPU/IO #############Set to one for testing/debugging
        $Results = $subFolders | ForEach-Object -Parallel {
            $inputdepth = $using:inputdepth
            $errorReportFile = $Using:errorReportFile
            $throttleLimit = $using:throttleLimit
            Import-Module Microsoft.PowerShell.Management
            Import-Module Microsoft.PowerShell.Utility
            function Get-NTFSPermissions {
                param (
                    [string]$path,
                    [int]$inputdepth,
                    [string]$errorpath
                )
                $folderDepth = $depth - $inputDepth #this is not right
                try {
                    $folder = Get-Item -Path $path -ErrorAction Stop
                    $acl = Get-Acl -Path $path -ErrorAction Stop
                    $rules = $acl.Access | Select-Object -Property IdentityReference, FileSystemRights, AccessControlType, IsInherited
                    foreach ($rule in $rules) {
                        $properties = @{
                            "Folder" = $folder.FullName
                            "Depth" = $folderDepth
                            "IdentityReference" = $rule.IdentityReference
                            "FileSystemRights" = $rule.FileSystemRights
                            "AccessControlType" = $rule.AccessControlType
                            "IsInherited" = $rule.IsInherited
                        }
                        #New-Object -TypeName PSObject -Property $properties | Export-Csv -Path $csvFile -Append -NoTypeInformation
                        $resultObj = New-Object -TypeName PSObject -Property $properties
                    }
                } catch {
                    if ($_.Exception.Message -match "The specified path, file name, or both are too long") {
                        # Long path handling omitted for parallel block for simplicity
                    } else {
                        Write-Warning "Failed to process $($path): $($_.Exception.Message)"
                        $errorProperties = @{
                            "Path" = $path
                            "Depth" = $folderDepth
                            "ErrorMessage" = $_.Exception.Message
                            "Time" = (Get-Date).ToString('s')
                        }
                        $errorObj = New-Object -TypeName PSObject -Property $errorProperties
                        if (-not (Test-Path $errorReportFile)) {
                            $errorObj | Export-Csv -Path $errorReportFile -NoTypeInformation
                        } else {
                            $errorObj | Export-Csv -Path $errorReportFile -Append -NoTypeInformation
                        }
                    }
                }
                # Recurse further
                try {
                    $subFolders = Get-ChildItem -Path $path -Directory -ErrorAction Stop
                } catch {
                    $errorProperties = @{
                        "Path" = $path
                        "Depth" = $folderDepth
                        "ErrorMessage" = $_.Exception.Message
                        "Time" = (Get-Date).ToString('s')
                    }
                    $errorObj = New-Object -TypeName PSObject -Property $errorProperties
                    if (-not (Test-Path $errorReportFile)) {
                        $errorObj | Export-Csv -Path $errorReportFile -NoTypeInformation
                    } else {
                        $errorObj | Export-Csv -Path $errorReportFile -Append -NoTypeInformation
                    }
                    return
                }
                foreach ($subFolder in $subFolders) {
                    Get-NTFSPermissions -path $subfolder.FullName -depth ($depth + 1)
                }
            }
            Get-NTFSPermissions -path $_.FullName -depth ($depth + 1) -errorpath $ReportFile -verbose
        }  -ThrottleLimit $throttleLimit #-ArgumentList $($path), $($depth)
        if ($results) {
            $results | Export-Csv -Path $csvFile -NoTypeInformation -Append
            Write-Host "parallel results exported to $csvFile"
            #$Results # debug
        }
        $Results | Export-csv -Path $csvFile -NoTypeInformation -Append
        Write-Host "Exported results to $csvFile"
    }
}

# Call the function for the root folder
Get-NTFSPermissions -path $rootFolder -depth 30 -errorpath $errorReportFile -verbose
