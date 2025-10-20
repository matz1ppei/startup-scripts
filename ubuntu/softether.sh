#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】SSH接続に使用するあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# --- 全体オプション ---
NEW_SSH_PORT=2222
# 管理作業用のOSユーザー名
USERNAME="vpsuser"

# --- SoftEther VPN 設定 ---
# VPN接続に使用するユーザー名
VPN_USER="vpn"
# VPN接続に使用するパスワード（ランダム生成）
VPN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
# L2TP/IPsecの事前共有キー（ランダム生成）
VPN_PSK=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
# 仮想ハブ名
VPN_HUB="DEFAULT"


echo "[INFO] Ubuntu with SoftEther VPN Serverのセットアップを開始します..."

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
echo "[2/8] ビルドツールとコンパイルに必要なライブラリをインストールしています..."
sudo apt install -y build-essential cmake make gcc zlib1g-dev libssl-dev libreadline-dev libncurses5-dev ufw jq curl
echo ""

# 3. 管理用OSユーザーの作成と設定
echo "[3/8] 管理用ユーザー ($USERNAME) を準備しています..."
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

# 4. SoftEther VPNのダウンロードとコンパイル
echo "[4/8] SoftEther VPNをダウンロードし、コンパイル・インストールします..."
# APIからLinux用64bitサーバーの直接のダウンロードURLを取得
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/SoftEtherVPN/SoftEtherVPN_Stable/releases/latest" | jq -r '.assets[] | select(.name | startswith("softether-vpnserver-") and endswith("linux-x64-64bit.tar.gz")) | .browser_download_url')

if [ -z "$DOWNLOAD_URL" ]; then
    echo "エラー: SoftEther VPNのダウンロードURLをAPIから取得できませんでした。"
    exit 1
fi

echo "[INFO] ダウンロードURL: $DOWNLOAD_URL"

cd /tmp
curl -L -o softether.tar.gz "$DOWNLOAD_URL"
tar -xzf softether.tar.gz
cd vpnserver
make
cd ..
sudo mv vpnserver /usr/local/
sudo ln -s /usr/local/vpnserver/vpnserver /usr/bin/vpnserver
sudo ln -s /usr/local/vpnserver/vpncmd /usr/bin/vpncmd
rm -rf /tmp/softether.tar.gz
echo ""

# 5. systemdサービスファイルの作成とサーバー起動
echo "[5/8] systemdサービスを作成し、VPNサーバーを起動します..."
sudo sh -c "cat <<EOF > /etc/systemd/system/vpnserver.service
[Unit]
Description=SoftEther VPN Server
After=network.target

[Service]
Type=forking
WorkingDirectory=/usr/local/vpnserver
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable vpnserver.service
sudo systemctl start vpnserver.service
# サーバーが起動するのを少し待つ
sleep 5
echo ""

# 6. SoftEther VPNの自動設定
echo "[6/8] vpncmdを使ってサーバーを自動設定します..."
ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
/usr/bin/vpncmd localhost /SERVER /CMD ServerPasswordSet ${ADMIN_PASSWORD}
/usr/bin/vpncmd localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubCreate ${VPN_HUB} /PASSWORD:
/usr/bin/vpncmd localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD IPsecEnable /L2TP:yes /L2TPRAW:no /ETHERIP:no /PSK:${VPN_PSK} /TAP:no
/usr/bin/vpncmd localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD UserCreate ${VPN_USER} /GROUP:none /REALNAME:none /NOTE:none
/usr/bin/vpncmd localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD UserPasswordSet ${VPN_USER} /PASSWORD:${VPN_PASSWORD}
echo ""

# 7. UFW (ファイアウォール) の設定
echo "[7/8] ファイアウォールを設定しています..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
sudo ufw allow 500,4500/udp  # L2TP/IPsec用
sudo ufw --force enable
echo "[INFO] UFWを有効化し、SSHとL2TP/IPsecのポートを許可しました。"
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
echo "---- VPN接続情報 ----"
echo "サーバーアドレス: <このサーバーのパブリックIPアドレス>"
echo "VPNタイプ: L2TP/IPsec"
echo "ユーザー名: $VPN_USER"
echo "パスワード: $VPN_PASSWORD"
echo "事前共有キー (PSK): $VPN_PSK"
echo "----------------------"
echo "サーバー管理パスワード: $ADMIN_PASSWORD （vpncmdでの管理に必要です。安全な場所に保管してください）"
echo ""
echo "---- 次のステップ ----"
echo "1. このスクリプトの実行後、新しいユーザーとポートでSSH接続してください:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<サーバーのIPアドレス>"
echo ""
echo "2. お使いのPCやスマートフォンのVPN設定画面で、上記のVPN接続情報を使って新しいVPN接続を構成してください。"
echo ""
