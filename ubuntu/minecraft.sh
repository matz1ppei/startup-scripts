#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】ここにあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# --- 全体オプション ---
NEW_SSH_PORT=2222
USERNAME="mcuser"

# --- Minecraftサーバー設定 ---
MINECRAFT_DIR="/opt/minecraft"
# メモリ割り当て (例: 2G, 1024M)
XMX="1024M"
XMS="1024M"
# server.properties の設定
MOTD="A Minecraft Server powered by Gemini"
GAME_MODE="survival"
DIFFICULTY="easy"

# --- RCON (リモートコンソール) 設定 ---
RCON_ENABLED=true
RCON_PORT=25575
# RCONパスワードをランダムに生成
RCON_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 15)


echo "[INFO] Ubuntu with Minecraftのセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
   echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの公開鍵に書き換えてください。"
   exit 1
fi

# 1. パッケージ更新
echo "[1/9] パッケージを更新しています..."
sudo apt update && sudo apt upgrade -y
echo ""

# 2. 必要なパッケージのインストール
echo "[2/9] Java、ビルドツール、その他のツールをインストールしています..."
sudo apt install -y default-jdk-headless jq git build-essential
echo ""

# 3. 作業用ユーザーの作成と設定
echo "[3/9] 作業用ユーザー ($USERNAME) を準備しています..."
if id "$USERNAME" &>/dev/null; then
    echo "[INFO] ユーザー $USERNAME は既に存在します。"
else
    echo "[INFO] ユーザー $USERNAME を作成します。"
    sudo useradd -m -s /bin/bash "$USERNAME"
    sudo usermod -aG sudo "$USERNAME"
fi

echo "[INFO] パスワードなしでsudoを実行できるように設定します..."
sudo bash -c "echo \"${USERNAME} ALL=(ALL:ALL) NOPASSWD:ALL\" > \"/etc/sudoers.d/90-${USERNAME}\""
sudo chmod 440 /etc/sudoers.d/90-${USERNAME}
echo ""

echo "[INFO] 公開鍵を $USER_HOME/.ssh/authorized_keys に設定します..."
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
sudo mkdir -p "$USER_HOME/.ssh"
sudo sh -c "echo '$PUBLIC_KEY' > '$USER_HOME/.ssh/authorized_keys'"
sudo chown -R "${USERNAME}:${USERNAME}" "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"
echo ""

# 4. Tailscaleのインストール
echo "[4/9] Tailscaleをインストールしています..."
curl -fsSL https://tailscale.com/install.sh | sh
echo ""

# 5. mcrcon (RCONクライアント) のインストール
echo "[5/9] RCONクライアント (mcrcon) をインストールしています..."
git clone https://github.com/Tiiffi/mcrcon.git /tmp/mcrcon
cd /tmp/mcrcon
make
sudo make install
cd -
rm -rf /tmp/mcrcon
echo ""

# 6. Minecraftサーバーのインストールと設定
echo "[6/9] Minecraftサーバーをインストールし、設定しています..."
sudo mkdir -p "$MINECRAFT_DIR"

echo "[INFO] 最新バージョンのサーバーURLを取得しています..."
MANIFEST_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
LATEST_VERSION=$(echo "$MANIFEST_URL" | jq -r '.latest.release')
VERSION_URL=$(echo "$MANIFEST_URL" | jq -r --arg VER "$LATEST_VERSION" '.versions[] | select(.id == $VER) | .url')
SERVER_JAR_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url')

echo "[INFO] 最新バージョン: $LATEST_VERSION"
echo "[INFO] サーバーJARをダウンロードしています: $SERVER_JAR_URL"
sudo wget -O "$MINECRAFT_DIR/server.jar" "$SERVER_JAR_URL"

echo "[INFO] EULAに同意します..."
sudo sh -c "echo 'eula=true' > $MINECRAFT_DIR/eula.txt"

echo "[INFO] server.properties を作成しています..."
sudo sh -c "cat <<EOF > $MINECRAFT_DIR/server.properties
motd=$MOTD
gamemode=$GAME_MODE
difficulty=$DIFFICULTY
enable-rcon=$RCON_ENABLED
rcon.port=$RCON_PORT
rcon.password=$RCON_PASSWORD
EOF"

sudo chown -R "${USERNAME}:${USERNAME}" "$MINECRAFT_DIR"
echo "[INFO] Minecraftサーバーのファイルを $MINECRAFT_DIR にインストールしました。"
echo ""

# 7. systemdサービスファイルの作成
echo "[7/9] systemdサービスを作成して、サーバーを自動起動するように設定します..."
sudo sh -c "cat <<EOF > /etc/systemd/system/minecraft.service
[Unit]
Description=Minecraft Server
After=network.target tailscale.service

[Service]
User=$USERNAME
WorkingDirectory=$MINECRAFT_DIR
ExecStart=/usr/bin/java -Xmx$XMX -Xms$XMS -jar server.jar nogui
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"

echo "[INFO] systemdデーモンをリロードし、Minecraftサービスを有効化します..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft.service
echo ""

# 8. UFW (ファイアウォール) の設定
echo "[8/9] ファイアウォールを設定しています..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
# RCONとMinecraft本体のポートはTailscale経由でのみアクセスするため、UFWでは許可しません。
sudo ufw --force enable
echo "[INFO] UFWを有効化し、SSH ($NEW_SSH_PORT) のポートのみを許可しました。"
echo ""

# 9. SSH設定の変更 (セキュリティ強化)
echo "[9/9] SSH設定を強化しています..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i -E "s/^#?Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo "[INFO] SSHポートを $NEW_SSH_PORT に変更し、パスワード認証とrootログインを無効化しました。"
echo ""

# 10. 完了メッセージ
echo "セットアップが完了しました！"
echo ""
echo "---- サーバー情報 ----"
echo "Minecraftサーバーは自動起動するように設定されています。"
echo "RCONパスワード: $RCON_PASSWORD"
echo ""
echo "---- 次のステップ ----"
echo "1. システムを再起動して、全てが自動起動することを確認してください。"
echo "   sudo reboot"
echo ""
echo "2. 再起動後、このサーバーに新しいユーザーとポートでSSH接続してください:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<サーバーのIPアドレス>"
echo ""
echo "3. 接続後、Tailscaleをセットアップします:"
echo "   sudo tailscale up"
echo "   表示されたURLにアクセスして、Tailscaleアカウントで認証してください。"
echo ""
echo "4. サーバーのTailscale IPアドレスを確認します:"
echo "   tailscale ip -4"
echo ""
echo "5. Minecraftクライアントのマルチプレイヤー設定で、サーバーアドレスに上記で確認したTailscale IPを入力して接続します。"
echo ""
echo "---- サーバー管理 ----"
echo "サーバーの起動/停止/状態確認はsystemctlコマンドを使用します。"
echo "  状態確認: sudo systemctl status minecraft"
echo "  起動:     sudo systemctl start minecraft"
echo "  停止:     sudo systemctl stop minecraft"
echo "  再起動:   sudo systemctl restart minecraft"
echo ""
echo "Minecraftサーバーへのコマンド実行はRCONを使用します。"
echo "RCONはTailscaleネットワーク経由でのみ接続可能です。"
echo "  例: mcrcon -H <Tailscale IP> -P $RCON_PORT -p \"$RCON_PASSWORD\" list"}

