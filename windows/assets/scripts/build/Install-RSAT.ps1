Write-Host "Installing Remote Server Administration Tools (RSAT)..."

$rsatFeatures = @(
    "Rsat.RemoteAccess.Management.Tools~~~~0.0.1.0",
    "Rsat.RemoteDesktop.Services.Tools~~~~0.0.1.0",
    "Rsat.ServerManager.Tools~~~~0.0.1.0"
)

foreach ($feature in $rsatFeatures) {
    Write-Host "Installing RSAT feature: $feature"
    try {
        Add-WindowsCapability -Online -Name $feature -ErrorAction Continue
    }
    catch {
        Write-Host "Failed to install $feature. Error: $_"
    }
}

Write-Host "RSAT installation complete"
