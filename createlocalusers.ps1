# Script to create local users for testing
$users = @(
    @{ Name = 'TestUser1'; Password = 'P@ssw0rd!123' },
    @{ Name = 'TestUser2'; Password = 'P@ssw0rd!123' }
)

foreach ($user in $users) {
    if (-not (Get-LocalUser -Name $user.Name -ErrorAction SilentlyContinue)) {
        try {
            $securePass = ConvertTo-SecureString $user.Password -AsPlainText -Force
            New-LocalUser -Name $user.Name -Password $securePass -FullName $user.Name -Description "Test user for NTFS permissions testing" -PasswordNeverExpires -UserMayNotChangePassword
            Write-Host "Created user: $($user.Name)"
        } catch {
            Write-Warning "Failed to create user $($user.Name): $($_.Exception.Message)"
        }
    } else {
        Write-Host "User $($user.Name) already exists."
    }
}
