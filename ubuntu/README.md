# Ubuntu Startup Scripts

This directory contains startup scripts for Ubuntu.

## Generating an SSH Key Pair (Common Prerequisite)

If you don't have an SSH key pair, you can generate one on your local machine (not on the server).

1.  Open a terminal on your computer (e.g., Terminal on macOS/Linux, or PowerShell/WSL on Windows).
2.  Run the following command. It is highly recommended to enter a strong passphrase when prompted.
    ```bash
    ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
    ```
3.  This will create two files, usually in `~/.ssh/`:
    *   `id_rsa` (your **private key** - keep this file secret and secure!)
    *   `id_rsa.pub` (your **public key** - this is what you will copy to servers).

4.  To display your public key for copying, use the `cat` command:
    ```bash
    cat ~/.ssh/id_rsa.pub
    ```
5.  Copy the entire output. This is the key you will paste into the `PUBLIC_KEY` variable in the scripts.

---

## Scripts

All scripts perform basic security hardening, including:
*   Creating a new user for daily operations.
*   Setting up SSH public key authentication for the new user.
*   Changing the default SSH port to `2222`.
*   Disabling password authentication and root login via SSH.
*   Configuring the UFW firewall.

### `gemini-cli.sh`

This script sets up a new Ubuntu server with the Gemini CLI.

#### Prerequisites

- Your SSH public key.

#### Usage

1.  Edit the `PUBLIC_KEY` variable in the script.
2.  Copy the script to your server (e.g., with `scp`).
3.  Connect to your server as `root`, make the script executable (`chmod +x`), and run it.

#### After Execution

- Log in as the new user (`vpsuser`) on the new SSH port (`2222`).
- It is recommended to reboot the server.

### `desktop.sh`

This script sets up an Ubuntu server with an XFCE desktop environment and Google Chrome, accessible via any RDP client.

#### Prerequisites

- Your SSH public key.
- A strong password for the new user (for RDP and `sudo`).

#### Usage

1.  Edit the `PUBLIC_KEY` and `PASSWORD` variables in the script.
2.  Copy the script to your server.
3.  Connect as `root`, make the script executable, and run it.

#### After Execution

- You can connect via SSH as `vpsuser` on port `2222`.
- You can connect via an RDP client to the server's IP address on port `3389` using the username `vpsuser` and the password you set.

### `minecraft.sh`

This script sets up a Minecraft Java Edition server that automatically runs the latest version. It uses Tailscale for secure access, meaning you don't need to open the Minecraft port to the public internet.

#### Prerequisites

- Your SSH public key.
- A Tailscale account.

#### Usage

1.  Edit the `PUBLIC_KEY` variable in the script. You can also adjust server settings like memory and MOTD.
2.  Copy the script to your server.
3.  Connect as `root`, make the script executable, and run it.

#### After Execution

1.  Log in via SSH as the new user (`mcuser`) on port `2222`.
2.  Run `sudo tailscale up` and authenticate in your browser.
3.  Find your server's Tailscale IP with `tailscale ip -4`.
4.  Connect to this IP address in your Minecraft client.
5.  The server runs as a `systemd` service and will start automatically on boot.

### `wordpress.sh`

This script sets up a WordPress site with an Nginx and MariaDB stack.

#### Prerequisites

- Your SSH public key.
- A domain name to host the WordPress site.

#### Usage

1.  Edit the `PUBLIC_KEY` and `DOMAIN_NAME` variables in the script.
2.  Copy the script to your server.
3.  Connect as `root`, make the script executable, and run it.

#### After Execution

- Log in via SSH as the new user (`vpsuser`) on port `2222`.
- Access your domain name in a web browser to complete the WordPress installation.
- The script will output the randomly generated database password, which you should store securely.