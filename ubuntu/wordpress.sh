#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】ここにあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"

# 【要編集】ここにあなたのドメイン名を入力してください
DOMAIN_NAME="example.com"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# --- WordPress設定 ---
WEB_ROOT="/var/www/${DOMAIN_NAME}"
DB_NAME=$(echo "${DOMAIN_NAME}" | sed 's/[^a-zA-Z0-9]//g')
DB_USER="wp_user"
DB_PASSWORD=$(openssl rand -base64 12) # ランダムなパスワードを生成

# --- SSH設定 ---
NEW_SSH_PORT=2222
USERNAME="vpsuser"   # 作業用ユーザー

echo "[INFO] Ubuntu with WordPress (Nginx + MariaDB) のセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
    echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの環境に合わせて書き換えてください。"
    exit 1
fi

# 1. パッケージ更新
echo "[1/9] パッケージ更新..."
sudo apt update && sudo apt upgrade -y
echo ""

# 2. ユーザー作成 & 公開鍵設定
echo "[2/9] 作業用ユーザー ($USERNAME) を準備しています..."
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

# 3. Webサーバー(Nginx)とPHPのインストール
echo "[3/9] NginxとPHP-FPMをインストール中..."
sudo apt install -y nginx mariadb-server php-fpm php-mysql php-curl php-gd php-xml php-mbstring php-xmlrpc php-zip php-intl
echo ""

# 4. データベース(MariaDB)の初期設定
echo "[4/9] MariaDBの初期設定を実行中..."
# sudo mysql_secure_installation # Note: This is interactive. Skipping for non-interactive script.
echo ""

# 5. WordPress用データベースとユーザーの作成
echo "[5/9] WordPress用データベースを作成中..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
echo ""

# 6. WordPressのインストール
echo "[6/9] WordPressをインストール中..."
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
sudo mv wordpress "${WEB_ROOT}"

# wp-config.php の設定
CONFIG_PATH="${WEB_ROOT}/wp-config.php"
sudo mv "${WEB_ROOT}/wp-config-sample.php" "${CONFIG_PATH}"
sudo sed -i "s/database_name_here/${DB_NAME}/" "${CONFIG_PATH}"
sudo sed -i "s/username_here/${DB_USER}/" "${CONFIG_PATH}"
sudo sed -i "s/password_here/${DB_PASSWORD}/" "${CONFIG_PATH}"

# Saltキーの自動生成
SALT=$(curl -sL https://api.wordpress.org/secret-key/1.1/salt/)
# Remove existing define lines for salts and replace them
START_MARKER=$(grep -n -F "define('AUTH_KEY'" "${CONFIG_PATH}" | cut -d: -f1)
END_MARKER=$(grep -n -F "define('NONCE_SALT'" "${CONFIG_PATH}" | cut -d: -f1)
if [ -n "$START_MARKER" ] && [ -n "$END_MARKER" ]; then
    sudo sed -i "${START_MARKER},${END_MARKER}d" "${CONFIG_PATH}"
fi
sudo bash -c 'printf "%s\n" "$1" >> "'"${CONFIG_PATH}"'"' _ "$SALT"
sudo bash -c 'echo "define('FS_METHOD', 'direct');" >> "'"${CONFIG_PATH}"'"'

# パーミッション設定
sudo chown -R www-data:www-data "${WEB_ROOT}"
sudo find "${WEB_ROOT}/" -type d -exec chmod 755 {} \;
sudo find "${WEB_ROOT}/" -type f -exec chmod 644 {} \;
echo ""

# 7. Nginxの設定
echo "[7/9] Nginxを設定中..."
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
sudo bash -c "cat > /etc/nginx/sites-available/${DOMAIN_NAME}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};
    root ${WEB_ROOT};

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?i\$args;
    }

    location ~ \.php\$
 {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/${DOMAIN_NAME}" /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx
echo ""

# 8. UFW設定（SSH, HTTP, HTTPS許可）
echo "[8/9] UFWを設定中..."
sudo ufw allow ${NEW_SSH_PORT}/tcp
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
echo ""

# 9. SSH設定変更（ポート + 公開鍵認証）
echo "[9/9] SSH設定を変更中..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i -E "s/^#?Port 22/Port ${NEW_SSH_PORT}/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo ""



echo "[INFO] Ubuntu with WordPress (Nginx + MariaDB) のセットアップが完了しました！"
echo ""
echo "--------------------------------------------------"
echo "データベース情報（大切に保管してください）"
echo "DB Name: ${DB_NAME}"
echo "DB User: ${DB_USER}"
echo "DB Pass: ${DB_PASSWORD}"
echo "--------------------------------------------------"
echo ""
echo "# 次のステップ"
echo " 1. サーバーを再起動してください。"
echo "    sudo reboot"
echo ""
echo " 2. ブラウザでドメインにアクセスし、WordPressの初期設定を完了させてください。"
echo "    http://${DOMAIN_NAME}/"
echo ""
echo "# SSHでの接続方法"
echo "  ssh -p ${NEW_SSH_PORT} ${USERNAME}@${DOMAIN_NAME}"
echo ""
