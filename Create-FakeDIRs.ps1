# Function to create a large folder structure with mixed permissions
function New-FakeDirectoryStructure {
    param(
        [string]$RootPath = "C:\Temp\FakeTestRoot",
        [int]$Depth = 5,
        [ValidateSet('inherited','direct','hybrid')][string]$PermissionsStyle = 'hybrid',
        [int]$TotalFolders = 100,
        [switch]$IncludeLongPaths = $false,
        [string]$CsvReport = "C:\Temp\FakeDirsReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    )

    # Ensure root exists
    if (-not (Test-Path $RootPath)) { New-Item -Path $RootPath -ItemType Directory | Out-Null }

    $createdFolders = @()
    $rand = [System.Random]::new()
    $users = @("Everyone","Users","Administrators","SYSTEM")
    $rights = @("FullControl","Modify","ReadAndExecute","Read","Write")

    function Set-FolderPermissions {
        param($Folder, $Style)
        $acl = $null
        try {
            $acl = Get-Acl $Folder
        } catch {
            Write-Warning ("[SKIP] Cannot get ACL for {0}: {1}" -f $Folder, $_.Exception.Message)
            return @() # Skip this folder
        }
        $permCount = $rand.Next(1,3)
        $entries = @()
        for ($i=0; $i -lt $permCount; $i++) {
            $user = $users[$rand.Next(0,$users.Count)]
            $right = $rights[$rand.Next(0,$rights.Count)]
            $type = if ($rand.Next(0,2) -eq 0) { 'Allow' } else { 'Deny' }
            $inherit = $true
            if ($Style -eq 'direct') { $inherit = $false }
            elseif ($Style -eq 'hybrid') { $inherit = ($rand.Next(0,2) -eq 0) }

            # Set inheritance and propagation flags
            if ($inherit) {
                $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                $propFlags = [System.Security.AccessControl.PropagationFlags]::None
            } else {
                $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::None
                $propFlags = [System.Security.AccessControl.PropagationFlags]::None
            }

            try {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, $right, $inheritFlags, $propFlags, $type)
                if ($rule -ne $null) {
                    $acl.AddAccessRule($rule)
                    $entries += [PSCustomObject]@{
                        Folder = $Folder
                        IdentityReference = $user
                        FileSystemRights = $right
                        AccessControlType = $type
                        IsInherited = $inherit
                    }
                }
            } catch {
                Write-Warning ("Failed to create or add access rule for {0} on {1}: {2}" -f $user, $Folder, $_.Exception.Message)
            }
        }
        # Always add FullControl for the current user
        try {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $fullControlRule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser, "FullControl", [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit, [System.Security.AccessControl.PropagationFlags]::None, "Allow")
            $acl.AddAccessRule($fullControlRule)
            $entries += [PSCustomObject]@{
                Folder = $Folder
                IdentityReference = $currentUser
                FileSystemRights = "FullControl"
                AccessControlType = "Allow"
                IsInherited = $true
            }
        } catch {
            Write-Warning ("Failed to add FullControl for current user on {0}: {1}" -f $Folder, $_.Exception.Message)
        }
        try {
            Set-Acl -Path $Folder -AclObject $acl
        } catch {
            Write-Warning ("[SKIP] Cannot set ACL for {0}: {1}" -f $Folder, $_.Exception.Message)
        }
        return $entries
    }

    $foldersToCreate = [Math]::Min($TotalFolders, [Math]::Pow(2, $Depth))
    $allEntries = @()
    $longPathBase = Join-Path $RootPath ('LongPath_' + ('x'*240))
    $foldersCreated = 0

    function Create-Branch {
        param($CurrentPath, $CurrentDepth)
        if ($foldersCreated -ge $foldersToCreate) { return }
        $foldersCreated++
        $entries = Set-FolderPermissions -Folder $CurrentPath -Style $PermissionsStyle
        $allEntries += $entries
        $createdFolders += $CurrentPath
        if ($CurrentDepth -lt $Depth) {
            $branchCount = $rand.Next(1,3)
            for ($i=0; $i -lt $branchCount; $i++) {
                if ($foldersCreated -ge $foldersToCreate) { break }
                $subName = "Sub$CurrentDepth-$i-" + ([guid]::NewGuid().ToString().Substring(0,8))
                $subPath = Join-Path $CurrentPath $subName
                New-Item -Path $subPath -ItemType Directory | Out-Null
                Create-Branch -CurrentPath $subPath -CurrentDepth ($CurrentDepth+1)
            }
        }
    }

    # Create normal structure
    Create-Branch -CurrentPath $RootPath -CurrentDepth 1

    # Optionally create some long path folders
    if ($IncludeLongPaths) {
        if (-not (Test-Path $longPathBase)) { New-Item -Path $longPathBase -ItemType Directory | Out-Null }
        for ($i=0; $i -lt 3; $i++) {
            $longPath = $longPathBase
            for ($j=0; $j -lt 10; $j++) {
                $longPath = Join-Path $longPath ("L" + ('x'*20) + "_$j")
                if (-not (Test-Path $longPath)) { New-Item -Path $longPath -ItemType Directory | Out-Null }
                $entries = Set-FolderPermissions -Folder $longPath -Style $PermissionsStyle
                $allEntries += $entries
            }
        }
    }

    # Output CSV report
    $allEntries | Select-Object Folder,IdentityReference,FileSystemRights,AccessControlType,IsInherited |
        Export-Csv -Path $CsvReport -NoTypeInformation

    Write-Host "Created $foldersCreated folders. Report: $CsvReport"
}

# Example usage:
# New-FakeDirectoryStructure -RootPath 'C:\Temp\FakeTestRoot' -Depth 4 -PermissionsStyle 'hybrid' -TotalFolders 50 -IncludeLongPaths -CsvReport 'C:\Temp\FakeDirsReport.csv'
