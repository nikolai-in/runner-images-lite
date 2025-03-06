Write-Host "Enabling Administrator account..."

# Enable the Administrator account
$result = net user Administrator /active:yes
Write-Host $result

# Verify the account is enabled
$userInfo = net user Administrator
Write-Host $userInfo

# Also make sure via Win32 API
$adminAccountStatus = ([ADSI]"WinNT://./Administrator").Properties["UserFlags"].Value
$isDisabled = $adminAccountStatus -band 0x2

if ($isDisabled) {
    Write-Host "WARNING: Administrator account is still disabled according to UserFlags!"
    
    # Try another method to enable it
    $user = [ADSI]"WinNT://./Administrator"
    $user.Properties["UserFlags"].Value = $adminAccountStatus -band (-bnot 0x2)
    $user.CommitChanges()
    
    # Verify again
    $adminAccountStatus = ([ADSI]"WinNT://./Administrator").Properties["UserFlags"].Value
    $isDisabled = $adminAccountStatus -band 0x2
    
    if ($isDisabled) {
        Write-Host "ERROR: Failed to enable Administrator account!"
        exit 1
    } else {
        Write-Host "Successfully enabled Administrator account via ADSI."
    }
} else {
    Write-Host "Administrator account is enabled."
}

Write-Host "Administrator account setup complete."
