# Windows Environment Setup Script

This script (`gemini-cli.ps1`) sets up a Windows environment with an SSH server and automatically installs and configures a suite of development tools.

## Features

This script automatically sets up the following components:

- **OpenSSH Server:**
  - Configures a secure SSH server that only allows public key authentication.
  - Automatically sets firewall rules for the specified port.
- **PowerShell 7:**
  - Automatically installs via `winget` if not already present.
  - Sets as the default shell for SSH connections.
- **Oh My Posh:**
  - Installs the `Oh My Posh` theme engine for beautiful prompts.
  - Automatically configures the profile to use the 'space' theme.
- **Nerd Font (Meslo):**
  - Interactively runs the installer for the `MesloLGM NF` font, which is required for Oh My Posh.
- **Volta:**
  - Installs the `Volta` JavaScript toolchain manager.
- **Node.js & Gemini CLI:**
  - Installs the LTS (Long-Term Support) version of Node.js via Volta.
  - Installs the `@google/gemini-cli` via Volta.

## Prerequisites

1.  **Administrator Privileges:** This script requires being run as an Administrator to install software and modify system settings.
2.  **Public Key:** Open the script file and paste your SSH public key (the string starting with `ssh-rsa ...`) into the `$PUBLIC_KEY` variable.

## How to Run

Open PowerShell as an Administrator and execute the following command:

```powershell
# Run with the Bypass flag to avoid execution policy issues.
powershell -ExecutionPolicy Bypass -File .\gemini-cli.ps1
```

During the script's execution, you will be prompted for interactive input once for the Nerd Font installation. Please follow the on-screen instructions.

## Post-Installation Manual Steps

After the script is complete, you must **configure your terminal's font settings** to correctly display Oh My Posh.

- **For Windows Terminal:**
  1.  Open Settings (`Ctrl` + `,`).
  2.  Select "Defaults" under the "Profiles" section.
  3.  Open the "Appearance" tab.
  4.  In the "Font face" dropdown, select `MesloLGM NF` and save.
