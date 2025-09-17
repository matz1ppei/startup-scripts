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
    $ruleName = "OpenSSH-Server-In-TCP-Port-$Port"
    if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
        Write-Host "Adding firewall rule for SSH (port $Port)..."
        New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd) on Port $Port" -Protocol TCP -LocalPort $Port -Action Allow -Direction Inbound -ErrorAction Stop
    } else {
        Write-Host "Firewall rule for SSH on port $Port already exists."
    }
}

# --- Main Execution ---

Test-Admin

Write-Host "Starting Windows setup for OpenSSH..." -ForegroundColor Green

Install-OpenSSHServer
Configure-SSHD -Port $SSH_PORT
Setup-SSHKeys -UserPublicKey $PUBLIC_KEY
Configure-Firewall -Port $SSH_PORT

Write-Host "`nSetup Complete!" -ForegroundColor Green
Write-Host "-------------------"
Write-Host "To connect to this machine, use: ssh -p $SSH_PORT $($env:USERNAME)@$($env:COMPUTERNAME)"