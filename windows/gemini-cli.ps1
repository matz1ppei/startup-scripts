#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Sets up a Windows environment with a secure OpenSSH server.
.DESCRIPTION
    This script performs the following actions:
    1. Installs and configures an OpenSSH server for secure remote access.
    2. Disables password authentication, allowing only public key authentication.
    3. Configures the Windows Firewall to allow SSH connections on the specified port.
.NOTES
    Author: Gemini
    Prerequisites: Windows PowerShell 5.1 or later.
    実行ポリシーのエラーが発生する場合は、次のコマンドを使用してこのスクリプトを実行できます:
    powershell -ExecutionPolicy Bypass -File .\gemini-cli.ps1
#>

#================================================================================
# --- CONFIGURATION --- (EDIT THIS SECTION)
#================================================================================

# Paste your SSH public key here. This will be used for SSH authentication.
# Example: "ssh-rsa AAAA... user@example.com"
$PUBLIC_KEY = ""

# Define the port for the SSH server.
$SSH_PORT = 22

#================================================================================
# --- SCRIPT BODY --- (DO NOT EDIT BELOW THIS LINE)
#================================================================================

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run with Administrator privileges. Please right-click the PowerShell script and select 'Run as Administrator'."
        exit 1
    }
}

function Install-OpenSSHServer {
    Write-Host "Checking OpenSSH Server feature..."
    $capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0"
    if ($capability.State -ne 'Installed') {
        Write-Host "Installing OpenSSH Server..."
        Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
        Write-Host "OpenSSH Server installed successfully."
    } else {
        Write-Host "OpenSSH Server is already installed."
    }
}

function Configure-SSHD {
    param (
        [int]$Port
    )

    Write-Host "Configuring OpenSSH server..."
    
    # Set service to start automatically and ensure it's running
    try {
        Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction Stop
        Start-Service -Name sshd -ErrorAction Stop
    } catch {
        Write-Error "Failed to start or configure the sshd service. $_"
        exit 1
    }

    # Modify sshd_config for security
    $sshdConfigFile = "$env:ProgramData\ssh\sshd_config"
    if (-not (Test-Path $sshdConfigFile)) {
        Write-Error "sshd_config not found at $sshdConfigFile"
        exit 1
    }

    Write-Host "Applying security settings to sshd_config..."
    (Get-Content $sshdConfigFile) | 
        ForEach-Object { $_ -replace '(?i)^#?Port.*$', "Port $Port" } |
        ForEach-Object { $_ -replace '(?i)^#?PasswordAuthentication.*$', 'PasswordAuthentication no' } | 
        ForEach-Object { $_ -replace '(?i)^#?PubkeyAuthentication.*$', 'PubkeyAuthentication yes' } |
        Set-Content $sshdConfigFile -Force

    # Restart service to apply changes
    Write-Host "Restarting sshd service to apply changes..."
    Restart-Service sshd -Force
}

function Setup-SSHKeys {
    param (
        [string]$UserPublicKey
    )

    if ([string]::IsNullOrEmpty($UserPublicKey)) {
        Write-Error "Public key is not set. Please edit the script and set the \$PUBLIC_KEY variable."
        exit 1
    }

    Write-Host "Setting up SSH authorized_keys for Administrator..."
    $sshDir = "$env:ProgramData\ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -Path $sshDir -ItemType Directory -Force | Out-Null
    }

    $authKeysFile = "$sshDir\administrators_authorized_keys"
    $UserPublicKey | Out-File -FilePath $authKeysFile -Encoding ascii -Force

    # The default permissions for the administrators_authorized_keys file are sufficient
    # when the file is created by an administrator. The previous explicit icacls command
    # was for user-specific files and is not needed here.
}

function Configure-Firewall {
    param (
        [int]$Port
    )
    Write-Host "Configuring Windows Firewall..."

    # Default rule name for port 22
    $defaultRuleName = "OpenSSH-Server-In-TCP"

    if ($Port -eq 22) {
        # If using the default port, ensure the default rule exists.
        # We don't create our own custom-named rule.
        $defaultRule = Get-NetFirewallRule -Name $defaultRuleName -ErrorAction SilentlyContinue
        if (-not $defaultRule) {
            Write-Host "Default firewall rule for port 22 not found. Creating it..."
            New-NetFirewallRule -Name $defaultRuleName -DisplayName "OpenSSH Server (sshd)" -Protocol TCP -LocalPort 22 -Action Allow -Direction Inbound -ErrorAction Stop
        } else {
            Write-Host "Default firewall rule for port 22 ('$defaultRuleName') already exists."
        }
    } else {
        # If a custom port is used, first remove the default rule for port 22 to avoid confusion.
        $defaultRule = Get-NetFirewallRule -Name $defaultRuleName -ErrorAction SilentlyContinue
        if ($defaultRule) {
            Write-Host "Custom port specified. Removing default firewall rule for port 22 ('$defaultRuleName')..."
            Remove-NetFirewallRule -Name $defaultRuleName
        }

        # Now, create the rule for the custom port.
        $customRuleName = "OpenSSH-Server-In-TCP-Port-$Port"
        if (-not (Get-NetFirewallRule -Name $customRuleName -ErrorAction SilentlyContinue)) {
            Write-Host "Adding firewall rule for SSH (port $Port)..."
            New-NetFirewallRule -Name $customRuleName -DisplayName "OpenSSH Server (sshd) on Port $Port" -Protocol TCP -LocalPort $Port -Action Allow -Direction Inbound -ErrorAction Stop
        } else {
            Write-Host "Firewall rule for SSH on port $Port ('$customRuleName') already exists."
        }
    }
}

function Set-DefaultShellToPowerShell {
    Write-Host "Setting default shell for SSH to PowerShell 7 (pwsh.exe)..."
    $openSshRegPath = "HKLM:\SOFTWARE\OpenSSH"
    $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

    # Pre-check if pwsh.exe exists. If not, try to install it using winget.
    if (-not (Test-Path $pwshPath)) {
        Write-Warning "PowerShell 7 not found. Attempting to install using winget..."
        try {
            winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
            # After installation, re-check for the path.
            if (-not (Test-Path $pwshPath)) {
                Write-Error "PowerShell 7 installation via winget may have succeeded, but the executable was not found at the expected path '$pwshPath'. Cannot set default shell."
                return
            }
            Write-Host "PowerShell 7 installed successfully."
        } catch {
            Write-Error "Failed to install PowerShell 7 using winget. Please install it manually and re-run the script. $_"
            return
        }
    }

    # Ensure the OpenSSH registry key exists before trying to set a property on it.
    if (-not (Test-Path $openSshRegPath)) {
        New-Item -Path $openSshRegPath -Force | Out-Null
    }

    try {
        New-ItemProperty -Path $openSshRegPath -Name "DefaultShell" -Value $pwshPath -PropertyType String -Force -ErrorAction Stop
        Write-Host "Default shell set to: $pwshPath"
    } catch {
        Write-Error "Failed to set default shell in registry. $_"
    }
}

function Install-OhMyPosh {
    Write-Host "Installing Oh My Posh..."
    # Check if Oh My Posh is already installed to avoid re-running winget
    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        try {
            winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
            Write-Host "Oh My Posh installed successfully."

            # Refresh environment variables to detect the new 'oh-my-posh' command in the current session.
            Write-Host "Refreshing environment variables..."
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch {
            Write-Error "Failed to install Oh My Posh using winget. Please install it manually. $_"
            return
        }
    } else {
        Write-Host "Oh My Posh is already installed."
    }

    Write-Host "Configuring PowerShell 7 profile for Oh My Posh..."
    # Explicitly define the path for the PowerShell 7 profile to avoid ambiguity.
    $pwshProfile = Join-Path -Path $HOME -ChildPath "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    
    # Ensure profile directory exists
    $pwshProfileDir = Split-Path -Path $pwshProfile -Parent
    if (-not (Test-Path $pwshProfileDir)) {
        New-Item -Path $pwshProfileDir -ItemType Directory -Force | Out-Null
    }
    # Ensure profile file exists
    if (-not (Test-Path $pwshProfile)) {
        New-Item -Path $pwshProfile -Type File -Force | Out-Null
    }

    # Add the init command if it's not already there
    $initCommand = "oh-my-posh init pwsh --config space | Invoke-Expression"
    if (-not (Select-String -Path $pwshProfile -Pattern $initCommand -Quiet)) {
        Add-Content -Path $pwshProfile -Value $initCommand
        Write-Host "Added Oh My Posh init command to PowerShell 7 profile."
    } else {
        Write-Host "Oh My Posh init command already present in PowerShell 7 profile."
    }
}

function Install-NerdFont {
    Write-Host "Installing Nerd Font (Meslo)..." -ForegroundColor Yellow
    Write-Host "The script will now pause and ask for input to install the font." -ForegroundColor Yellow
    Write-Host "Please follow the on-screen prompts from Oh My Posh." -ForegroundColor Yellow
    try {
        # This command is interactive and will require user input.
        oh-my-posh font install meslo
        Write-Host "Font installation process complete."
    } catch {
        Write-Error "An error occurred during font installation. Please try installing manually. $_"
    }
}

function Install-VoltaAndNode {
    Write-Host "Installing Volta and Node.js LTS..."

    # 1. Install Volta if not already present
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Write-Host "Volta not found. Downloading and installing..."
        $voltaVersion = "1.1.1"
        $msiUrl = "https://github.com/volta-cli/volta/releases/download/v$($voltaVersion)/volta-$($voltaVersion)-windows-x86_64.msi"
        $msiPath = Join-Path -Path $env:TEMP -ChildPath "volta.msi"

        try {
            # Download the installer
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
            Write-Host "Volta installer downloaded to $msiPath"

            # Run the installer silently
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
            Write-Host "Volta installation complete."

            # Refresh environment variables to detect the new 'volta' command
            Write-Host "Refreshing environment variables..."
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch {
            Write-Error "Failed to download or install Volta. $_"
            return
        } finally {
            # Clean up the installer
            if (Test-Path $msiPath) {
                Remove-Item $msiPath
            }
        }
    } else {
        Write-Host "Volta is already installed."
    }

    # 2. Install Node.js LTS using Volta
    Write-Host "Installing Node.js LTS via Volta..."
    try {
        volta install node@lts
        Write-Host "Node.js LTS installed successfully."
    } catch {
        Write-Error "Failed to install Node.js using Volta. $_"
        # If Node fails, we can't continue.
        return
    }

    # 3. Install Gemini CLI using Volta
    Write-Host "Installing Gemini CLI via Volta..."
    try {
        volta install @google/gemini-cli
        Write-Host "Gemini CLI installed successfully."
    } catch {
        Write-Error "Failed to install Gemini CLI using Volta. $_"
    }
}

# --- Main Execution ---

Test-Admin

Write-Host "Starting Windows setup for OpenSSH..." -ForegroundColor Green

Install-OpenSSHServer
Configure-SSHD -Port $SSH_PORT
Setup-SSHKeys -UserPublicKey $PUBLIC_KEY
Configure-Firewall -Port $SSH_PORT
Set-DefaultShellToPowerShell
Install-OhMyPosh
Install-NerdFont
Install-VoltaAndNode

Write-Host "`nSetup Complete!" -ForegroundColor Green
Write-Host "-------------------"
Write-Host "To connect to this machine, use: ssh -p $SSH_PORT $($env:USERNAME)@$($env:COMPUTERNAME)"
