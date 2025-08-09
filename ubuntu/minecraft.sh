#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】ここにあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# --- オプション ---
NEW_SSH_PORT=2222
USERNAME="mcuser"
MINECRAFT_DIR="/opt/minecraft"
# メモリ割り当て (例: 2G, 1024M)
XMX="1024M"
XMS="1024M"

echo "[INFO] Ubuntu with Minecraftのセットアップを開始します..."

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
echo "[2/8] Javaとその他のツールをインストールしています..."
sudo apt install -y default-jdk-headless tmux jq
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
echo "[4/8] Tailscaleをインストールしています..."
curl -fsSL https://tailscale.com/install.sh | sh
echo ""

# 5. Minecraftサーバーのインストール
echo "[5/8] Minecraftサーバーをインストールしています..."
sudo mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

echo "[INFO] 最新バージョンのサーバーURLを取得しています..."
MANIFEST_URL=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
LATEST_VERSION=$(echo "$MANIFEST_URL" | jq -r '.latest.release')
VERSION_URL=$(echo "$MANIFEST_URL" | jq -r --arg VER "$LATEST_VERSION" '.versions[] | select(.id == $VER) | .url')
SERVER_JAR_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url')

echo "[INFO] 最新バージョン: $LATEST_VERSION"
echo "[INFO] サーバーJARをダウンロードしています: $SERVER_JAR_URL"
sudo wget -O server.jar "$SERVER_JAR_URL"

echo "[INFO] EULAに同意します..."
sudo sh -c 'echo "eula=true" > eula.txt'

echo "[INFO] 起動スクリプトを作成しています..."
sudo sh -c "cat <<EOF > run.sh
#!/bin/bash
cd $MINECRAFT_DIR
/usr/bin/java -Xmx${XMX} -Xms${XMS} -jar server.jar nogui
EOF"
sudo chmod +x run.sh

sudo chown -R "${USERNAME}:${USERNAME}" "$MINECRAFT_DIR"
echo "[INFO] Minecraftサーバーのファイルを $MINECRAFT_DIR にインストールしました。"
echo ""

# 6. UFW (ファイアウォール) の設定
echo "[6/8] ファイアウォールを設定しています..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
# Minecraft用のポート(25565)はTailscale経由でアクセスするため、UFWでは許可しません。
sudo ufw --force enable
echo "[INFO] UFWを有効化し、SSH ($NEW_SSH_PORT) のポートを許可しました。"
echo ""

# 7. SSH設定の変更 (セキュリティ強化)
echo "[7/8] SSH設定を強化しています..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i -E "s/^#?Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo "[INFO] SSHポートを $NEW_SSH_PORT に変更し、パスワード認証とrootログインを無効化しました。"
echo ""

# 8. 完了メッセージ
echo "[8/8] セットアップが完了しました！"
echo ""
echo "---- 次のステップ ----"
echo "1. このサーバーに新しいユーザーとポートでSSH接続してください:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<サーバーのIPアドレス>"
echo ""
echo "2. 接続後、Tailscaleをセットアップします:"
echo "   sudo tailscale up"
echo "   表示されたURLにアクセスして、Tailscaleアカウントで認証してください。"
echo ""
echo "3. サーバーのTailscale IPアドレスを確認します:"
echo "   tailscale ip -4"
echo ""
echo "4. tmuxセッションを開始してMinecraftサーバーを起動します:"
echo "   tmux new -s minecraft"
echo "   sudo /opt/minecraft/run.sh"
echo ""
echo "5. Minecraftクライアントのマルチプレイヤー設定で、サーバーアドレスに上記で確認したTailscale IPを入力して接続します。"
echo ""
echo "6. tmuxセッションからデタッチするには、Ctrl+b を押してから d を押します。"
echo "   再度アタッチするには 'tmux a -t minecraft' を実行します。"
echo "----------------------"

