#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】SSH接続に使用するあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# --- 全体オプション ---
NEW_SSH_PORT=2222
USERNAME="mcserver"

# --- Minecraft Bedrockサーバー設定 ---
MINECRAFT_DIR="/opt/minecraft-bedrock"
# server.properties の設定
SERVER_NAME="Bedrock Server by Gemini"
GAME_MODE="survival"
DIFFICULTY="normal"


echo "[INFO] Ubuntu with Minecraft Bedrock Serverのセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
   echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの公開鍵に書き換えてください。"
   exit 1
fi

# 1. パッケージ更新
echo "[1/8] パッケージを更新しています..."
sudo apt update && sudo apt upgrade -y
echo ""

# 2. 必要なパッケージのインストール
echo "[2/8] 必要なツール (unzip, curl, tmux, ufw, jq) をインストールしています..."
sudo apt install -y unzip curl tmux ufw jq
echo ""

# 3. 作業用ユーザーの作成と設定
echo "[3/8] 作業用ユーザー ($USERNAME) を準備しています..."
if id "$USERNAME" &>/dev/null; then
    echo "[INFO] ユーザー $USERNAME は既に存在します。"
else
    echo "[INFO] ユーザー $USERNAME を作成します。"
    sudo useradd -m -s /bin/bash "$USERNAME"
    sudo usermod -aG sudo "$USERNAME"
fi

echo "[INFO] パスワードなしでsudoを実行できるように設定します..."
sudo sh -c "echo '${USERNAME} ALL=(ALL:ALL) NOPASSWD:ALL' > '/etc/sudoers.d/90-${USERNAME}'"
sudo chmod 440 /etc/sudoers.d/90-${USERNAME}

echo "[INFO] 公開鍵を authorized_keys に設定します..."
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
sudo mkdir -p "$USER_HOME/.ssh"
sudo sh -c "echo '$PUBLIC_KEY' > '$USER_HOME/.ssh/authorized_keys'"
sudo chown -R "${USERNAME}:${USERNAME}" "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"
echo ""

# 4. Tailscaleのインストール
echo "[4/8] Tailscaleをインストールしています..."
curl -fsSL https://tailscale.com/install.sh | sh
echo ""

# 5. Minecraft Bedrockサーバーのインストールと設定
echo "[5/8] Minecraft Bedrockサーバーをインストールし、設定しています..."
sudo mkdir -p "$MINECRAFT_DIR"

echo "[INFO] APIから最新バージョンのサーバーURLを取得しています..."
DOWNLOAD_URL="$(curl -fsSL https://net-secondary.web.minecraft-services.net/api/v1.0/download/links | jq -r '.result.links[] | select(.downloadType=="serverBedrockLinux") | .downloadUrl')"

if [ -z "$DOWNLOAD_URL" ]; then
    echo "エラー: Minecraft BedrockサーバーのダウンロードURLをAPIから取得できませんでした。"
    exit 1
fi

echo "[INFO] サーバーZIPをダウンロードしています: $DOWNLOAD_URL"
sudo curl -L -o "$MINECRAFT_DIR/bedrock-server.zip" \
  -A "Mozilla/5.0 (X11; Linux x86_64) Chrome/122 Safari/537.36" \
  "$DOWNLOAD_URL"

echo "[INFO] サーバーファイルを展開しています..."
sudo unzip -o "$MINECRAFT_DIR/bedrock-server.zip" -d "$MINECRAFT_DIR"

echo "[INFO] server.properties を作成しています..."
sudo sh -c "cat <<EOF > $MINECRAFT_DIR/server.properties
server-name=$SERVER_NAME
gamemode=$GAME_MODE
difficulty=$DIFFICULTY
EOF"

sudo chown -R "${USERNAME}:${USERNAME}" "$MINECRAFT_DIR"
echo "[INFO] Minecraft Bedrockサーバーのファイルを $MINECRAFT_DIR にインストールしました。"
echo ""

# 6. systemdサービスファイルの作成
echo "[6/8] systemdサービスを作成して、サーバーを自動起動するように設定します..."
sudo sh -c "cat <<EOF > /etc/systemd/system/minecraft-bedrock.service
[Unit]
Description=Minecraft Bedrock Server
After=network.target tailscale.service

[Service]
User=$USERNAME
WorkingDirectory=$MINECRAFT_DIR
ExecStart=/usr/bin/tmux new-session -d -s minecraft-bedrock '$MINECRAFT_DIR/bedrock_server'
ExecStop=/usr/bin/tmux send-keys -t minecraft-bedrock \"stop\" C-m
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"

echo "[INFO] systemdデーモンをリロードし、Minecraftサービスを有効化します..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft-bedrock.service
echo ""

# 7. UFW (ファイアウォール) の設定
echo "[7/8] ファイアウォールを設定しています..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
# Minecraft本体のポート(19132/udp)はTailscale経由でのみアクセスするため、UFWでは許可しません。
sudo ufw --force enable
echo "[INFO] UFWを有効化し、SSH ($NEW_SSH_PORT) のポートのみを許可しました。"
echo ""

# 8. SSH設定の変更 (セキュリティ強化)
echo "[8/8] SSH設定を強化しています..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i -E "s/^#?Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo "[INFO] SSHポートを $NEW_SSH_PORT に変更し、パスワード認証とrootログインを無効化しました。"
echo ""

# 9. 完了メッセージ
echo "セットアップが完了しました！"
echo ""
echo "---- 次のステップ ----"
echo "1. システムを再起動して、全てが自動起動することを確認してください。"
echo "   sudo reboot"

echo "2. 再起動後、このサーバーに新しいユーザーとポートでSSH接続してください:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<サーバーのIPアドレス>"

echo "3. 接続後、Tailscaleをセットアップします:"
echo "   sudo tailscale up"
echo "   表示されたURLにアクセスして、Tailscaleアカウントで認証してください。"

echo "4. サーバーのTailscale IPアドレスを確認します:"
echo "   tailscale ip -4"

echo "5. Minecraftクライアントのマルチプレイヤー設定で、サーバーアドレスに上記で確認したTailscale IPを入力して接続します。(ポートはデフォルトの19132)"

echo "---- サーバー管理 ----"
echo "サーバーの起動/停止/状態確認はsystemctlコマンドを使用します。"
echo "  状態確認: sudo systemctl status minecraft-bedrock"
echo "  起動:     sudo systemctl start minecraft-bedrock"
echo "  停止:     sudo systemctl stop minecraft-bedrock"
echo "  再起動:   sudo systemctl restart minecraft-bedrock"

echo "Minecraftサーバーのコンソールに接続するにはtmuxを使用します。"
echo "  接続: tmux attach-session -t minecraft-bedrock"
echo "  切断: Ctrl+B を押してから D"