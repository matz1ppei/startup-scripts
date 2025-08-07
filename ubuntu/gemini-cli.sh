#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】ここにあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

NEW_SSH_PORT=2222
USERNAME="vpsuser"   # 作業用ユーザー

echo "[INFO] Ubuntu with Gemini CLIのセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
    echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの公開鍵に書き換えてください。"
    exit 1
fi

# 1. パッケージ更新
echo "[1/6] パッケージ更新..."
sudo apt update && sudo apt upgrade -y
echo ""

# 2. ユーザー作成 & 公開鍵設定
echo "[2/6] 作業用ユーザー ($USERNAME) を準備しています..."
if id "$USERNAME" &>/dev/null; then
    echo "[INFO] ユーザー $USERNAME は既に存在します。"
else
    echo "[INFO] ユーザー $USERNAME を作成します。"
    sudo adduser --disabled-password --gecos "" $USERNAME
    sudo usermod -aG sudo $USERNAME
fi

echo "[INFO] パスワードなしでsudoを実行できるように設定します..."
sudo bash -c "echo \"${USERNAME} ALL=(ALL:ALL) NOPASSWD:ALL\" > \"/etc/sudoers.d/90-${USERNAME}\""
sudo chmod 440 /etc/sudoers.d/90-${USERNAME}
echo ""

echo "[INFO] ユーザー $USERNAME の公開鍵を設定します..."
USER_HOME=$(getent passwd $USERNAME | cut -d: -f6)
sudo mkdir -p "${USER_HOME}/.ssh"
sudo bash -c "echo \"${PUBLIC_KEY}\" > \"${USER_HOME}/.ssh/authorized_keys\""
sudo chmod 700 "${USER_HOME}/.ssh"
sudo chmod 600 "${USER_HOME}/.ssh/authorized_keys"
sudo chown -R ${USERNAME}:${USERNAME} "${USER_HOME}/.ssh"
echo ""

# 3. Node.js(Volta)のインストール
echo "[3/6] Voltaをインストール中..."
sudo -u ${USERNAME} bash -c 'curl https://get.volta.sh | bash'
echo ""

# 4. Node.jsとGemini Cliのインストール
echo "[4/6] Node.jsとGemini Cliをインストール中..."
sudo -u ${USERNAME} bash -c "${USER_HOME}/.volta/bin/volta install node"
sudo -u ${USERNAME} bash -c "${USER_HOME}/.volta/bin/volta install @google/gemini-cli"
echo ""

# 5. UFW設定（SSHポート許可）
echo "[5/6] UFWを設定中..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
sudo ufw --force enable
echo ""

# 6. SSH設定変更（ポート + 公開鍵認証）
echo "[6/6] SSH設定を変更中..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i "s/^#?Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config
sudo sed -i "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo sed -i "s/^#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sudo sed -i "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo ""


echo "[INFO] Ubuntu with Gemini CLIのセットアップが完了しました！"
echo ""
echo "次回は SSH 接続時にポート ${NEW_SSH_PORT} を使用してください："
echo "  ssh -p ${NEW_SSH_PORT} ${USERNAME}@サーバIP"
echo ""
echo "Geminiを初めて起動する場合にはログインURL取得のために任意のプロンプトを実行してください。"
echo "  gemini -p 'Hi'"
echo ""
echo "また、システム全体を最新の状態にするためにサーバーを再起動することをお勧めします。"
echo "  sudo reboot"
