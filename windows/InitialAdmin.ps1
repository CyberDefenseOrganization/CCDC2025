# Ensure the script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Error "This script must be run from an elevated (Administrator) PowerShell session. Exiting."
    exit 1
}

# Enable/configure WinRM locally
Write-Host " Enabling WinRM via Enable-PSRemoting…" -ForegroundColor Cyan
Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue

if (-not $? -or ((Get-Service WinRM).Status -ne 'Running')) {
    Write-Error "  Failed to enable PowerShell Remoting or start the WinRM service. Exiting."
    exit 1
}
Write-Host "  WinRM has been enabled/configured locally." -ForegroundColor Green

# Prompt for remote computer
$remoteComputer = Read-Host "`nEnter the remote computer name or IP (e.g., 192.168.1.90)"

# Configure TrustedHosts
Write-Host "`nConfiguring TrustedHosts via WinRM CLI…" -ForegroundColor Cyan
$rawConfig = & winrm get winrm/config/client 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "  Failed to retrieve TrustedHosts config."
    exit 1
}

$thLine = $rawConfig | Where-Object { $_ -match '^\s*TrustedHosts\s*=' }
$currentTH = if ($thLine) { ($thLine -split '=')[1].Trim() } else { "" }

if ([string]::IsNullOrWhiteSpace($currentTH)) {
    $newTH = $remoteComputer
    Write-Host "  No existing TrustedHosts. Setting to '$remoteComputer'." -ForegroundColor Yellow
} elseif ($currentTH -notlike "*$remoteComputer*") {
    $newTH = "$currentTH,$remoteComputer"
    Write-Host "  Appending '$remoteComputer' to existing TrustedHosts: $currentTH" -ForegroundColor Yellow
} else {
    $newTH = $currentTH
    Write-Host "  '$remoteComputer' is already in TrustedHosts." -ForegroundColor Green
}

& winrm set winrm/config/client "@{TrustedHosts=`"$newTH`"}" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "  Failed to set TrustedHosts."
    exit 1
}
Write-Host "  TrustedHosts successfully set to: $newTH" -ForegroundColor Green

# Get credentials
$adminCred = Get-Credential -Message "`nEnter credentials for an account with user-creation rights on '$remoteComputer'"

# Define function to create user
function Create-RemoteUser {
    param (
        [Parameter(Mandatory)] [string] $Username,
        [Parameter(Mandatory)] [securestring] $Password,
        [Parameter(Mandatory)] [bool] $IsAdmin
    )

    Invoke-Command -ComputerName $remoteComputer -Credential $adminCred -ScriptBlock {
        param($Name, $SecurePwd, $AddToAdmins)

        $domainUser = $false

        # Try to check if the user exists in the domain
        try {
            $null = Get-ADUser -Identity $Name -ErrorAction Stop
            $domainUser = $true
        } catch {
            $domainUser = $false
        }

        if (-not $domainUser) {
            # Create the local user
            New-LocalUser -Name $Name -Password $SecurePwd -FullName $Name -Description "Created via script" `
                          -AccountNeverExpires:$true -PasswordNeverExpires:$false
            if (-not $?) {
                Write-Error "  Failed to create local user '$Name'."
                return
            }
            Write-Output "  Local user '$Name' created successfully."
        }

        if ($AddToAdmins) {
            $localGroups = @("Administrators", "Remote Desktop Users")
            foreach ($grp in $localGroups) {
                Write-Output "  Attempting to add '$Name' to '$grp' (local)..."
                $output = net localgroup "$grp" "$Name" /add 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Output "    Successfully added '$Name' to '$grp'"
                } else {
                    Write-Output "    Failed to add '$Name' to '$grp'. Error: $output"
                }
            }

            $domainGroups = @("Domain Admins", "Enterprise Admins")
            foreach ($grp in $domainGroups) {
                Write-Output "  Attempting to add '$Name' to '$grp' (domain)..."
                $output = net group "$grp" "$Name" /add /domain 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Output "    Successfully added '$Name' to '$grp'"
                } else {
                    Write-Output "    Failed to add '$Name' to '$grp'. Error: $output"
                }
            }
        } else {
            Write-Output "  '$Name' is a standard user and will not be added to groups."
        }

    } -ArgumentList $Username, $Password, $IsAdmin

    if (-not $?) {
        Write-Error "  Remote command failed for user '$Username'."
    }
}

# Prompt for privileged users
do {
    $numAdmins = [int](Read-Host "`nHow many privileged (Administrator) users to create? (0 to skip)")
} while ($numAdmins -lt 0)

for ($i = 1; $i -le $numAdmins; $i++) {
    $admName = Read-Host "  Enter username for privileged user #$i"
    $admPwd  = Read-Host "  Enter password for '$admName'" -AsSecureString
    Write-Host "  → Creating privileged user '$admName'…" -ForegroundColor Cyan
    Create-RemoteUser -Username $admName -Password $admPwd -IsAdmin $true
}

# Prompt for unprivileged users
do {
    $numUsers = [int](Read-Host "`nHow many unprivileged (standard) users to create? (0 to skip)")
} while ($numUsers -lt 0)

for ($j = 1; $j -le $numUsers; $j++) {
    $userName = Read-Host "  Enter username for unprivileged user #$j"
    $userPwd  = Read-Host "  Enter password for '$userName'" -AsSecureString
    Write-Host "  → Creating standard user '$userName'…" -ForegroundColor Cyan
    Create-RemoteUser -Username $userName -Password $userPwd -IsAdmin $false
}

Write-Host "`nUser creation process completed." -ForegroundColor Green

#Real Jon Fortnite
