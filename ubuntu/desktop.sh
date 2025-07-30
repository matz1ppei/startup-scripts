#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】ここにあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

NEW_SSH_PORT=2222
USERNAME="vpsuser"   # 作業用ユーザー

echo "[INFO] Ubuntuデスクトップのセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
    echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの公開鍵に書き換えてください。"
    exit 1
fi

# 1. パッケージ更新
echo "[INFO] パッケージ更新..."
sudo apt update && sudo apt upgrade -y
echo ""

# 2. デスクトップ環境と関連パッケージのインストール
echo "[INFO] Xfce, XRDP, Google Chromeをインストール中..."
# Xfceデスクトップ環境、XRDP、その他ツールをまとめてインストール
sudo apt install -y xfce4 xfce4-goodies xrdp wget
echo ""

# 3. ブラウザ（Google Chrome）のインストール
echo "[INFO] Google Chromeをダウンロードしてインストール中..."
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb
rm ./google-chrome-stable_current_amd64.deb
echo ""

# 4. ユーザー作成 & 公開鍵設定
if id "$USERNAME" &>/dev/null; then
    echo "[INFO] ユーザー $USERNAME は既に存在します。"
else
    echo "[INFO] ユーザー $USERNAME を作成します..."
    sudo adduser --disabled-password --gecos "" $USERNAME
    sudo usermod -aG sudo $USERNAME
fi

echo "[INFO] ユーザー $USERNAME の公開鍵を設定します..."
USER_HOME=$(getent passwd $USERNAME | cut -d: -f6)
sudo mkdir -p "${USER_HOME}/.ssh"
sudo bash -c "echo \"${PUBLIC_KEY}\" > \"${USER_HOME}/.ssh/authorized_keys\""
sudo chmod 700 "${USER_HOME}/.ssh"
sudo chmod 600 "${USER_HOME}/.ssh/authorized_keys"
sudo chown -R ${USERNAME}:${USERNAME} "${USER_HOME}/.ssh"
echo ""

# 5. リモートデスクトップ設定
echo "[INFO] リモートデスクトップ(XRDP)を設定中..."
# Xfceをデフォルトのセッションとして設定
echo xfce4-session > "${USER_HOME}/.xsession"
sudo chown ${USERNAME}:${USERNAME} "${USER_HOME}/.xsession"

# XRDPが証明書を読み取れるようにパーミッションを設定
sudo adduser xrdp ssl-cert
# XRDPサービスを再起動して設定を反映
sudo systemctl restart xrdp
echo ""

# 6. UFW設定（SSHポート、リモートデスクトップの許可）
echo "[INFO] UFWを設定中..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
sudo ufw allow 3389/tcp
sudo ufw --force enable
echo ""

# 7. SSH設定変更（ポート + 公開鍵認証）
echo "[INFO] SSH設定を変更中..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i "s/^Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config
sudo sed -i "s/^#Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config
sudo sed -i "s/^PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo sed -i "s/^#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo sed -i "s/^#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sudo sed -i "s/^PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo ""


echo "[INFO] Ubuntuデスクトップのセットアップが完了しました！"
echo ""
echo "============================================================"
echo "【重要】今後の接続情報"
echo ""
echo "▼ SSH接続"
echo "  ssh -p ${NEW_SSH_PORT} ${USERNAME}@サーバIP"
echo ""
echo "▼ リモートデスクトップ接続"
echo "  - RDPクライアント（Windowsのリモートデスクトップ接続など）を使用"
echo "  - コンピューター: サーバIP"
echo "  - ユーザー名: ${USERNAME}"
echo ""
echo "システム全体を最新の状態にするためにサーバーを再起動することをお勧めします。"
echo "  sudo reboot"
echo "============================================================"
