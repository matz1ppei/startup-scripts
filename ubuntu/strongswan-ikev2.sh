#!/bin/bash
set -e

# ==== 設定項目 ====
# ▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼▼
# 【要編集】SSH接続に使用するあなたの公開鍵を貼り付けてください
PUBLIC_KEY="ssh-rsa AAAA... user@example.com"

# --- 全体オプション ---
# 管理作業用のOSユーザー名
USERNAME="vpsuser"
# SSHポート番号
NEW_SSH_PORT=2222

# --- IKEv2 VPN 設定 ---
# VPN接続に使用するユーザー名
VPN_USER="vpnuser"
# VPN接続に使用するパスワード（ブランクの場合はランダム生成）
VPN_PASSWORD=""
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲


# --- スクリプト内部設定 ---
# VPNクライアントに割り当てる仮想IPアドレスのプール
VPN_SUBNET="10.10.10.0/24"
# VPNクライアントに通知するDNSサーバ
VPN_DNS="8.8.8.8,1.1.1.1"


echo "[INFO] Ubuntu with IKEv2 VPN Server (strongSwan) のセットアップを開始します..."

# 事前チェック
if [[ $PUBLIC_KEY == "ssh-rsa AAAA... user@example.com" ]]; then
   echo "エラー: スクリプト内のPUBLIC_KEY変数をあなたの公開鍵に書き換えてください。"
   exit 1
fi
if [ -z "$VPN_PASSWORD" ]; then
    VPN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo "[INFO] VPNパスワードが空のため、ランダムなパスワードを生成しました。"
fi
if [[ $EUID -ne 0 ]]; then
   echo "エラー: このスクリプトはroot権限で実行する必要があります。"
   exit 1
fi


# 1. パッケージ更新と必要パッケージのインストール
echo "[1/10] パッケージを更新し、必要パッケージをインストールしています..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y strongswan strongswan-pki libstrongswan-extra-plugins ufw curl
echo ""

# 2. 管理用OSユーザーの作成と設定
echo "[2/10] 管理用ユーザー ($USERNAME) を準備しています..."
if id "$USERNAME" &>/dev/null; then
    echo "[INFO] ユーザー $USERNAME は既に存在します。"
else
    echo "[INFO] ユーザー $USERNAME を作成します。"
    sudo useradd -m -s /bin/bash "$USERNAME"
    sudo usermod -aG sudo "$USERNAME"
fi

echo "[INFO] パスワードなしでsudoを実行できるように設定します..."
sudo sh -c "echo '${USERNAME} ALL=(ALL:ALL) NOPASSWD:ALL' > '/etc/sudoers.d/90-${USERNAME}'"
sudo chmod 440 "/etc/sudoers.d/90-${USERNAME}"

echo "[INFO] 公開鍵を authorized_keys に設定します..."
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
sudo mkdir -p "$USER_HOME/.ssh"
sudo sh -c "echo '$PUBLIC_KEY' > '$USER_HOME/.ssh/authorized_keys'"
sudo chown -R "${USERNAME}:${USERNAME}" "$USER_HOME/.ssh"
sudo chmod 700 "$USER_HOME/.ssh"
sudo chmod 600 "$USER_HOME/.ssh/authorized_keys"
echo ""

# 3. サーバーのパブリックIPアドレスを取得
echo "[3/10] サーバーのパブリックIPアドレスを取得しています..."
SERVER_IP=$(curl -s https://ipinfo.io/ip)
if [ -z "$SERVER_IP" ]; then
    echo "エラー: パブリックIPアドレスの取得に失敗しました。"
    exit 1
fi
echo "[INFO] サーバーIP: $SERVER_IP"
echo ""

# 4. 証明書の生成と配置
echo "[4/10] 自己署名証明書を生成しています..."
# CA
sudo ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca.key.pem
sudo ipsec pki --self --ca --lifetime 3650 \
    --in /etc/ipsec.d/private/ca.key.pem \
    --type rsa --dn "CN=VPN CA" --outform pem > /etc/ipsec.d/cacerts/ca.crt.pem

# Server
sudo ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/server.key.pem
sudo ipsec pki --pub --in /etc/ipsec.d/private/server.key.pem --type rsa | \
    sudo ipsec pki --issue --lifetime 1825 \
        --cacert /etc/ipsec.d/cacerts/ca.crt.pem \
        --cakey /etc/ipsec.d/private/ca.key.pem \
        --dn "CN=$SERVER_IP" --san "$SERVER_IP" \
        --flag serverAuth --flag ikeIntermediate --outform pem > /etc/ipsec.d/certs/server.crt.pem
echo "[INFO] 証明書の生成が完了しました。"
echo ""

# 5. strongSwan (IKEv2) の設定
echo "[5/10] strongSwan (IKEv2) の設定を行っています..."
sudo sh -c "cat <<EOF > /etc/ipsec.conf
config setup
    charondebug=\"ike 1, knl 1, cfg 0\"
    uniqueids=no

conn %default
    keyexchange=ikev2
    ike=aes256-sha384-ecp384,aes256-sha256-modp2048,aes256gcm16-sha256-ecp384
    esp=aes256-sha256,aes256gcm16
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftsubnet=0.0.0.0/0
    leftcert=/etc/ipsec.d/certs/server.crt.pem
    right=%any
    rightsourceip=${VPN_SUBNET}
    rightdns=${VPN_DNS}

conn ikev2-vpn
    rightauth=eap-mschapv2
    eap_identity=%identity
    auto=add
EOF"

sudo sh -c "cat <<EOF > /etc/ipsec.secrets
: RSA \"/etc/ipsec.d/private/server.key.pem\"
${VPN_USER} : EAP \"${VPN_PASSWORD}\"
EOF"
echo "[INFO] ipsec.conf と ipsec.secrets の設定が完了しました。"
echo ""

# 6. ネットワーク設定 (sysctl)
echo "[6/10] IPフォワーディングを有効にしています..."
sudo sh -c "cat <<EOF > /etc/sysctl.d/99-vpn.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF"
sudo sysctl -p /etc/sysctl.d/99-vpn.conf
echo ""

# 7. UFW (ファイアウォール) の設定
echo "[7/10] ファイアウォール (UFW) を設定しています..."
# プライマリネットワークインターフェースを自動検出
PRIMARY_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
if [ -z "$PRIMARY_INTERFACE" ]; then
    echo "エラー: プライマリネットワークインターフェースの検出に失敗しました。"
    exit 1
fi
echo "[INFO] プライマリインターフェース: $PRIMARY_INTERFACE"

UFW_BEFORE_RULES="/etc/ufw/before.rules"
UFW_NAT_RULES="*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s ${VPN_SUBNET} -o ${PRIMARY_INTERFACE} -m policy --dir out --pol ipsec -j ACCEPT
-A POSTROUTING -s ${VPN_SUBNET} -o ${PRIMARY_INTERFACE} -j MASQUERADE
COMMIT"

# Check if NAT rules already exist. Add them if they don't.
if ! grep -q "MASQUERADE" "$UFW_BEFORE_RULES"; then
    # Use a temporary file to prepend the rules safely
    TEMP_FILE=$(mktemp)
    echo "$UFW_NAT_RULES" > "$TEMP_FILE"
    cat "$UFW_BEFORE_RULES" >> "$TEMP_FILE"
    sudo mv "$TEMP_FILE" "$UFW_BEFORE_RULES"
    sudo chown root:root "$UFW_BEFORE_RULES"
    sudo chmod 644 "$UFW_BEFORE_RULES"
fi

sudo ufw allow ${NEW_SSH_PORT}/tcp
sudo ufw allow 500,4500/udp
sudo ufw --force enable
echo ""

# 8. SSH設定の変更 (セキュリティ強化)
echo "[8/10] SSH設定を強化しています..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old
sudo sed -i -E "s/^#?Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#?PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
sudo sed -i -E "s/^#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config
sudo systemctl restart ssh
echo ""

# 9. サービスの再起動
echo "[9/10] strongSwanサービスを再起動しています..."
sudo systemctl restart strongswan-starter
echo ""

# 10. 完了メッセージ
echo "[10/10] セットアップが完了しました！"
echo ""
echo "===================================================================="
echo " IKEv2 VPN Server セットアップ完了"
echo "===================================================================="
echo ""
echo "以下の情報を各クライアント（iPhone, Macなど）のVPN設定に入力してください。"
echo ""
echo "  サーバーアドレス: ${SERVER_IP}"
echo "  リモートID:      ${SERVER_IP}"
echo "  VPNタイプ:       IKEv2"
echo "  認証:            ユーザ名"
echo "  ユーザ名:        ${VPN_USER}"
echo "  パスワード:      ${VPN_PASSWORD}"
echo ""
echo "--------------------------------------------------------------------"
echo " ★★★【重要】クライアントでの証明書インストール手順 ★★★"
echo "--------------------------------------------------------------------"
echo "1. 以下の '-----BEGIN CERTIFICATE-----' から '-----END CERTIFICATE-----' までを"
echo "   すべてコピーし、お使いのPCで 'ca.cer' という名前のファイルとして保存してください。"
echo ""
echo "2. 作成した 'ca.cer' ファイルを、VPN接続したい端末（iPhone, Macなど）に"
echo "   メール添付などの方法で送信してください。"
echo ""
echo "3. 端末でそのファイルを開くと、証明書プロファイルのインストール画面が表示されます。"
echo "   画面の指示に従い、インストールを完了させてください。"
echo "   (iPhoneの場合: 設定 > 一般 > VPNとデバイス管理 にインストールされます)"
echo ""
echo "4. 【iPhone/iPadのみ】インストール後、さらに信頼設定が必要です。"
echo "   設定 > 一般 > 情報 > 証明書信頼設定 を開き、"
echo "   今インストールした 'VPN CA' をオンにしてください。"
echo ""
echo "上記の手順が完了してから、VPN接続を試してください。"
echo "===================================================================="
echo ""
cat /etc/ipsec.d/cacerts/ca.crt.pem
echo ""
echo "===================================================================="
echo ""
echo "今後のSSHでの接続方法:"
echo "  ssh -p ${NEW_SSH_PORT} ${USERNAME}@${SERVER_IP}"
echo ""
