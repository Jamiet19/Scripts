# NTFS Permissions Reporting Script

This PowerShell script recursively reports NTFS permissions for a specified root folder, exporting results to a CSV file. It supports long path handling and parallel processing for improved performance.

## Features

- **Recursively scans** all subfolders from a specified root directory.
- **Exports NTFS permissions** (including user/group, rights, inheritance, etc.) to a CSV file.
- **Handles long file paths** using a temporary drive mapping.
- **Parallel processing** for faster enumeration (requires PowerShell 7+).
- **Error reporting** to a separate CSV file.
- **Automatic PowerShell 7 installation** if not already present (Windows only).

## Requirements

- **PowerShell 7+** (the script checks and installs it if missing on Windows).
- Sufficient permissions to read NTFS ACLs and write output files.

## Usage

1. **Configure the script variables** at the top of the script:
    - `$rootFolder` – The root directory to scan.
    - Output paths for `$csvFile` and `$errorReportFile`.

2. **Run the script as Administrator** (required for installing PowerShell 7 and accessing all folders):

    ```powershell
    .\O_PermsReportingV2_4.ps1
    ```

3. **Output:**
    - NTFS permissions are exported to the specified CSV file.
    - Errors are logged to the error report CSV.

## Key Functions

- `Ensure-PowerShell7`  
  Checks for PowerShell 7 and installs it if missing.

- `Map-TempDriveForLongPath`  
  Maps a temporary drive to handle long file paths.

- `Get-NTFSPermissions`  
  Recursively collects NTFS permissions and outputs results.

## Notes

- For large directory trees, adjust the `$throttleLimit` variable to control parallelism.
- The script is designed for Windows environments.
- If you encounter permission errors, run the script as an administrator.

## Example Output

| Folder                         | Depth | IdentityReference | FileSystemRights | AccessControlType | IsInherited |
|--------------------------------|-------|------------------|------------------|-------------------|-------------|
| O:\Safety - Space and Defence  | 0     | DOMAIN\User      | FullControl      | Allow             | False       |

## License

MIT License

---

**Author:** Jamie Toplis  
**Last updated:** May 2025