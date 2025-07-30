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

### `gemini-cli.sh`

This script sets up a new Ubuntu server with the Gemini CLI. It also performs basic security hardening, including:

*   Creating a new user (`vpsuser`) for daily operations.
*   Setting up SSH public key authentication for the new user.
*   Changing the default SSH port to `2222`.
*   Disabling password authentication and root login via SSH.
*   Configuring the UFW firewall to allow the new SSH port.

#### Prerequisites

Before running the script, you **MUST** edit `gemini-cli.sh` and replace the placeholder public key with your own (see how to generate and find it in the section above).

1.  Open `gemini-cli.sh` with a text editor.
2.  Find the line `PUBLIC_KEY="ssh-rsa AAAA... user@example.com"`.
3.  Replace the entire string with your actual SSH public key.

#### Usage

1.  **Copy the script to your server:**
    ```bash
    # Replace YOUR_SERVER_IP with your server's IP address
    scp ./gemini-cli.sh root@YOUR_SERVER_IP:/root/
    ```

2.  **Connect to your server and run the script:**
    ```bash
    ssh root@YOUR_SERVER_IP

    # Grant execute permission
    chmod +x /root/gemini-cli.sh

    # Run the script
    /root/gemini-cli.sh
    ```

#### After Execution

Once the script is complete:

*   Your SSH session might be disconnected.
*   You must use the new port and username to log in next time.
    ```bash
    # Replace YOUR_SERVER_IP with your server's IP address
    ssh -p 2222 vpsuser@YOUR_SERVER_IP
    ```
*   It is recommended to reboot the server to apply all changes.
    ```bash
    sudo reboot
    ```
