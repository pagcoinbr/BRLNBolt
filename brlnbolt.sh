#!/bin/bash

# Define as variáveis da URL do repositório do Tor
TOR_LINIK=https://deb.torproject.org/torproject.org
TOR_GPGLINK=https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc
# Define a variável de versão do LND
LND_VERSION=0.18.3
MAIN_DIR=/data
LN_DDIR=/data/lnd
LNDG_DIR=/home/admin/lndg
VERSION_THUB=0.13.31

update_and_upgrade() {
sudo apt update && sudo apt full-upgrade -y
}

create_main_dir() {
  sudo usermod -a -G sudo,adm,cdrom,dip,plugdev,lxd $USER
  [[ ! -d $MAIN_DIR ]] && sudo mkdir $MAIN_DIR
  sudo chown admin:admin $MAIN_DIR
}

configure_ufw() {
  sudo sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
  sudo ufw logging off
  sudo ufw allow 22/tcp comment 'allow SSH from anywhere'
  sudo ufw --force enable
}

install_tor() {
  sudo apt install -y apt-transport-https
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] $TOR_LINIK jammy main
deb-src [arch=amd64 signed-by=/usr/share/keyrings/tor-archive-keyring.gpg] $TOR_LINIK jammy main" | sudo tee /etc/apt/sources.list.d/tor.list
  sudo su -c "wget -qO- $TOR_GPGLINK | gpg --dearmor | tee /usr/share/keyrings/tor-archive-keyring.gpg >/dev/null"
  sudo apt update && sudo apt install -y tor deb.torproject.org-keyring
  sudo sed -i 's/^#ControlPort 9051/ControlPort 9051/' /etc/tor/torrc
  sudo systemctl reload tor
  if sudo ss -tulpn | grep -q "127.0.0.1:9050" && sudo ss -tulpn | grep -q "127.0.0.1:9051"; then
    echo "Tor está configurado corretamente e ouvindo nas portas 9050 e 9051."
    wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -
    sudo apt update && sudo apt install -y i2pd
    echo "i2pd instalado com sucesso."
  else
    echo "Erro: Tor não está ouvindo nas portas corretas."
  fi
}

download_lnd() {
  if [[ ! -d /tmp ]]; then
    mkdir /tmp
  else
    echo "Diretório /tmp já existe."
  fi
  wget https://github.com/lightningnetwork/lnd/releases/download/v$LND_VERSION-beta/lnd-linux-amd64-v$LND_VERSION-beta.tar.gz
  wget https://github.com/lightningnetwork/lnd/releases/download/v$LND_VERSION-beta/manifest-v$LND_VERSION-beta.txt.ots
  wget https://github.com/lightningnetwork/lnd/releases/download/v$LND_VERSION-beta/manifest-v$LND_VERSION-beta.txt
  wget https://github.com/lightningnetwork/lnd/releases/download/v$LND_VERSION-beta/manifest-roasbeef-v$LND_VERSION-beta.sig.ots
  wget https://github.com/lightningnetwork/lnd/releases/download/v$LND_VERSION-beta/manifest-roasbeef-v$LND_VERSION-beta.sig
  sha256sum --check manifest-v$LND_VERSION-beta.txt --ignore-missing
  curl https://raw.githubusercontent.com/lightningnetwork/lnd/master/scripts/keys/roasbeef.asc | gpg --import
  gpg --verify manifest-roasbeef-v$LND_VERSION-beta.sig manifest-v$LND_VERSION-beta.txt
  if [ $? -ne 0 ]; then
    echo "####################################################################################### WARNING: GPG SIGNATURE NOT VERIFIED.##################################################################################################################################################"
    exit 1
  fi
  tar -xzf lnd-linux-amd64-v$LND_VERSION-beta.tar.gz
  sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-amd64-v$LND_VERSION-beta/lnd lnd-linux-amd64-v$LND_VERSION-beta/lncli
  sudo rm -r lnd-linux-amd64-v$LND_VERSION-beta lnd-linux-amd64-v$LND_VERSION-beta.tar.gz manifest-roasbeef-v$LND_VERSION-beta.sig manifest-roasbeef-v$LND_VERSION-beta.sig.ots manifest-v$LND_VERSION-beta.txt manifest-v$LND_VERSION-beta.txt.ots
}

configure_lnd() {
  sudo usermod -aG debian-tor admin
  sudo chmod 640 /run/tor/control.authcookie
  sudo chmod 750 /run/tor
  sudo usermod -a -G debian-tor admin
  sudo mkdir -p $LN_DDIR
  sudo chown -R admin:admin $LN_DDIR
  ln -s $LN_DDIR /home/admin/.lnd
  echo "$password" > $LN_DDIR/password.txt
  chmod 600 $LN_DDIR/password.txt
  cat << EOF > $LN_DDIR/lnd.conf
# BRLN: lnd configuration
# /data/lnd/lnd.conf

[Application Options]
alias=$alias | BR⚡LN
debuglevel=info
maxpendingchannels=3

# Rest and gRPC API to LAN
# Rest Externo para acesso Zeus Wallet
restlisten=0.0.0.0:8080
rpclisten=localhost:10009

# Password: automatically unlock wallet with the password in this file
wallet-unlock-password-file=/data/lnd/password.txt
wallet-unlock-allow-create=true

# Automatically regenerate certificate when near expiration
tlsautorefresh=true
# Do not include the interface IPs or the system hostname in TLS certificate.
tlsdisableautofill=true

#FOR CLEARNET USE ONLY - Uncomment and fill out with your address
#listen=0.0.0.0:9740
#externalhosts=myadress.ddns.net:9740

# Channel settings
bitcoin.basefee=1000
bitcoin.feerate=500
minchansize=50000
maxchansize=10000000
accept-keysend=true
accept-amp=true
coop-close-target-confs=288
bitcoin.defaultchanconfs=2
bitcoin.timelockdelta=80
allow-circular-route=true
bitcoin.defaultchanconfs=2
max-cltv-expiry=2016
max-commit-fee-rate-anchors=100

routing.strictgraphpruning=true
rpcmiddleware.enable=true
routerrpc.minrtprob=0.001
routerrpc.apriori.hopprob=0.7
routerrpc.apriori.weight=0.3
routerrpc.apriori.penaltyhalflife=2h
routerrpc.attemptcost=10
routerrpc.attemptcostppm=100
routerrpc.maxmchistory=100000
caches.channel-cache-size=100000

# Watchtower
wtclient.active=true

# Performance
sync-freelist=false
gc-canceled-invoices-on-startup=true
gc-canceled-invoices-on-the-fly=true
ignore-historical-gossip-filters=1
stagger-initial-reconnect=true
payments-expiration-grace-period=10000h

# Database
[bolt]
db.bolt.auto-compact=false
db.bolt.auto-compact-min-age=0h

[Bitcoin]
bitcoin.mainnet=true
bitcoin.node=bitcoind

[bitcoind]

#Bitcoin VPS
bitcoind.rpchost=bitcoin.br-ln.com:8085
bitcoind.rpcuser=$bitcoind_rpcuser
bitcoind.rpcpass=$bitcoind_rpcpass
bitcoind.zmqpubrawblock=tcp://bitcoin.br-ln.com:28332
bitcoind.zmqpubrawtx=tcp://bitcoin.br-ln.com:28333

[tor]
# If clearnet active, change the 2 lines below to true and false
tor.skip-proxy-for-clearnet-targets=false
tor.streamisolation=true
tor.active=true
tor.v3=true
EOF
  echo "Configuração concluída com sucesso!"
  ln -s $LN_DDIR /home/admin/.lnd
  sudo chmod -R g+X $LN_DDIR
  sudo chmod 640 /run/tor/control.authcookie
  sudo chmod 750 /run/tor
}

create_lnd_service() {
  sudo bash -c 'cat << EOF > /etc/systemd/system/lnd.service
# MiniBolt: systemd unit for lnd
# /etc/systemd/system/lnd.service

[Unit]
Description=Lightning Network Daemon

[Service]
ExecStart=/usr/local/bin/lnd
ExecStop=/usr/local/bin/lncli stop

# Process management
####################
Restart=on-failure
RestartSec=60
Type=notify
TimeoutStartSec=1200
TimeoutStopSec=3600

# Directory creation and permissions
####################################
RuntimeDirectory=lightningd
RuntimeDirectoryMode=0710
User=admin
Group=admin

# Hardening Measures
####################
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF'
  ln -s $LN_DDIR /home/admin/.lnd
  sudo chmod -R g+X $LN_DDIR
  sudo chmod 640 /run/tor/control.authcookie
  sudo chmod 750 /run/tor
  sudo systemctl enable lnd
  sudo systemctl start lnd
  echo "Depois, digite a senha 2x para confirmar e pressione 'n' para criar uma nova cateira, digite o "password" e pressione *enter* para criar uma nova carteira."
  lncli create
  }

install_bitcoin () {

sudo apt update && sudo apt full-upgrade -y
cd
cd /tmp
VERSION=28.0
wget https://bitcoincore.org/bin/bitcoin-core-$VERSION/bitcoin-$VERSION-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-$VERSION/SHA256SUMS
wget https://bitcoincore.org/bin/bitcoin-core-$VERSION/SHA256SUMS.asc
sha256sum --ignore-missing --check SHA256SUMS
if [ $? -ne 0 ]; then
  echo "######################################################## Erro: SHA256SUMS não verificado.###########################################################################################################"
  exit 1
fi
curl -s "https://api.github.com/repositories/355107265/contents/builder-keys" | grep download_url | grep -oE "https://[a-zA-Z0-9./-]+" | while read url; do curl -s "$url" | gpg --import; done
gpg --verify SHA256SUMS.asc
#Verifica integridade do arquivo
if [ $? -ne 0 ]; then
  echo "#####################################################################################Erro: SHA256SUMS.asc não verificado.############################################################################################"
  exit 1
fi
tar -xvf bitcoin-$VERSION-x86_64-linux-gnu.tar.gz
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-$VERSION/bin/bitcoin-cli bitcoin-$VERSION/bin/bitcoind
bitcoind --version
sudo rm -r bitcoin-$VERSION bitcoin-$VERSION-x86_64-linux-gnu.tar.gz SHA256SUMS SHA256SUMS.asc
cd
sudo mkdir -p /data/bitcoin
sudo chown admin:admin /data/bitcoin
ln -s /data/bitcoin /home/admin/.bitcoin
sudo bash -c "cat <<EOF > /home/admin/.bitcoin/bitcoin.conf
# BRLN: bitcoind configuration
# /home/bitcoin/.bitcoin/bitcoin.conf

# Bitcoin daemon
server=1
txindex=1

# Disable integrated Bitcoin Core wallet
disablewallet=1

# Additional logs
debug=tor
#debug=i2p

# Assign to the cookie file read permission to the Bitcoin group users
startupnotify=chmod g+r /home/admin/.bitcoin/.cookie

# Disable debug.log
nodebuglogfile=1

# Avoid assuming that a block and its ancestors are valid,
# and potentially skipping their script verification.
# We will set it to 0, to verify all.
assumevalid=0

# Enable all compact filters
blockfilterindex=1

# Serve compact block filters to peers per BIP 157
peerblockfilters=1

# Maintain coinstats index used by the gettxoutsetinfo RPC
coinstatsindex=1

# Network
listen=1

## P2P bind
bind=127.0.0.1

## Proxify clearnet outbound connections using Tor SOCKS5 proxy
proxy=127.0.0.1:9050

## I2P SAM proxy to reach I2P peers and accept I2P connections
#i2psam=127.0.0.1:7656

# Connections
rpcuser=brlnbolt
rpcpassword=MyFirstBitcoinNode2024
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
zmqpubrawblock=tcp://127.0.0.1:28332
zmqpubrawtx=tcp://127.0.0.1:28333

# Enable ZMQ blockhash notification (for Fulcrum)
zmqpubhashblock=tcp://127.0.0.1:8433

# Initial block download optimizations (set dbcache size in megabytes 
# (4 to 16384, default: 300) according to the available RAM of your device,
# recommended: dbcache=1/2 x RAM available e.g: 4GB RAM -> dbcache=2048)
# Remember to comment after IBD (Initial Block Download)!
dbcache=2048
blocksonly=1
EOF"
sudo chown -R admin:admin /home/admin/.bitcoin
sudo chmod 750 /home/admin/.bitcoin
sudo chmod 640 /home/admin/.bitcoin/bitcoin.conf
ln -s /data/bitcoin /home/admin/.bitcoin
sudo bash -c "cat <<EOF > /etc/systemd/system/bitcoind.service
# MiniBolt: systemd unit for bitcoind
# /etc/systemd/system/bitcoind.service

[Unit]
Description=Bitcoin Core Daemon
Requires=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/bitcoind -daemon \
                                  -pid=/run/bitcoind/bitcoind.pid \
                                  -conf=/home/$USER/.bitcoin/bitcoin.conf \
                                  -datadir=/home/$USER/.bitcoin \
                                  -startupnotify="chmod g+r /home/$USER/.bitcoin/.cookie"
# Process management
####################
Type=exec
NotifyAccess=all
PIDFile=/run/bitcoind/bitcoind.pid

Restart=on-failure
TimeoutStartSec=infinity
TimeoutStopSec=600

# Directory creation and permissions
####################################
User=admin
Group=admin
RuntimeDirectory=bitcoind
RuntimeDirectoryMode=0710
UMask=0027

# Hardening measures
####################
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF"
sudo systemctl daemon-reload
sudo systemctl enable bitcoind
sudo systemctl start bitcoind
}

install_nodejs() {
  curl -sL https://deb.nodesource.com/setup_21.x | sudo -E bash -
  sudo apt-get install nodejs -y
  
}

install_bos() {
  mkdir -p ~/.npm-global
  npm config set prefix '~/.npm-global'
if ! grep -q 'PATH="$HOME/.npm-global/bin:$PATH"' ~/.profile; then
  echo 'PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.profile
fi
  source ~/.profile
  npm i -g balanceofsatoshis
  bos --version
  sudo bash -c 'echo "127.0.0.1" >> /etc/hosts'
  sudo chown -R $USER:$USER /data/lnd
  sudo chmod -R 755 /data/lnd
  export BOS_DEFAULT_LND_PATH=/data/lnd
  mkdir -p ~/.bos/$nome_do_seu_node
  base64 -w0 /data/lnd/tls.cert > /data/lnd/tls.cert.base64
  base64 -w0 /data/lnd/data/chain/bitcoin/mainnet/admin.macaroon > /data/lnd/data/chain/bitcoin/mainnet/admin.macaroon.base64
  cert_base64=$(cat /data/lnd/tls.cert.base64)
  macaroon_base64=$(cat /data/lnd/data/chain/bitcoin/mainnet/admin.macaroon.base64)
  bash -c "cat <<EOF > ~/.bos/$nome_do_seu_node/credentials.json
{
  "cert": "$cert_base64",
  "macaroon": "$macaroon_base64",
  "socket": "localhost:10009"
}
EOF"
  sudo bash -c "cat <<EOF > /etc/systemd/system/bos-telegram.service
# Systemd unit for Bos-Telegram Bot
# /etc/systemd/system/bos-telegram.service
# Substitua as variáveis iniciadas com \$ com suas informações
# Não esquece de apagar o \$

[Unit]
Description=bos-telegram
Wants=lnd.service
After=lnd.service

[Service]
ExecStart=/home/admin/.npm-global/bin/bos telegram --use-small-units --connect <seu_connect_code_aqui>
User=admin
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal
Environment=BOS_DEFAULT_LND_PATH=/data/lnd

[Install]
WantedBy=multi-user.target
EOF"
  sudo systemctl daemon-reload
  sudo systemctl start bos-telegram.service
  sudo systemctl enable bos-telegram.service
}

install_thunderhub() {
  node -v
  npm -v
  sudo apt update && sudo apt full-upgrade -y
  cd
  curl https://github.com/apotdevin.gpg | gpg --import
  git clone --branch v$VERSION_THUB https://github.com/apotdevin/thunderhub.git && cd thunderhub
  git verify-commit v$VERSION_THUB
  sudo apt update && sudo apt full-upgrade -y
  npm install
  npm run build
sudo ufw allow 3000/tcp comment 'allow ThunderHub SSL from anywhere'
cp .env .env.local
sed -i '51s|.*|ACCOUNT_CONFIG_PATH="/home/admin/thunderhub/thubConfig.yaml"|' .env.local
bash -c "cat <<EOF > thubConfig.yaml
masterPassword: 'PASSWORD'
accounts:
  - name: 'MiniBolt'
    serverUrl: '127.0.0.1:10009'
    macaroonPath: '/data/lnd/data/chain/bitcoin/mainnet/admin.macaroon'
    certificatePath: '/data/lnd/tls.cert'
    password: '[E] ThunderHub password'
EOF"
sed -i "7s|\[E\] ThunderHub password|$senha|" thubConfig.yaml
sudo bash -c 'cat <<EOF > /etc/systemd/system/thunderhub.service
# MiniBolt: systemd unit for Thunderhub
# /etc/systemd/system/thunderhub.service

[Unit]
Description=ThunderHub
Requires=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/admin/thunderhub
ExecStart=/usr/bin/npm run start

User=admin

# Process management
####################
TimeoutSec=300

# Hardening Measures
####################
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl start thunderhub.service
sudo systemctl enable thunderhub.service
}

install_lndg () {
sudo ufw allow 8889/tcp comment 'allow lndg SSL from anywhere'
cd
git clone https://github.com/cryptosharks131/lndg.git
cd lndg
sudo apt install -y virtualenv
virtualenv -p python3 .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install whitenoise
.venv/bin/python initialize.py --whitenoise
sudo tee /etc/systemd/system/lndg-controller.service > /dev/null <<EOF
[Unit]
Description=Controlador de backend para Lndg

[Service]
Environment=PYTHONUNBUFFERED=1
User=admin
Group=admin
ExecStart=$LNDG_DIR/.venv/bin/python $LNDG_DIR/controller.py
StandardOutput=append:/var/log/lndg-controller.log
StandardError=append:/var/log/lndg-controller.log
Restart=always
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF
sudo tee /etc/systemd/system/lndg.service > /dev/null  <<EOF
[Unit]
Description=LNDG Django Server
After=network.target

[Service]
Environment=PYTHONUNBUFFERED=1
User=admin
Group=admin
WorkingDirectory=$LNDG_DIR
ExecStart=$LNDG_DIR/.venv/bin/python $LNDG_DIR/manage.py runserver 0.0.0.0:8889
StandardOutput=append:/var/log/lndg.log
StandardError=append:/var/log/lndg.log
Restart=always
RestartSec=5
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable lndg-controller.service
sudo systemctl start lndg-controller.service
sudo systemctl enable lndg.service
sudo systemctl start lndg.service
}


main() {
    read -p "Digite o nome do seu node (sem tags como | BRLN): " nome_do_seu_node
read -p "Digite a senha para ThunderHub: " senha
read -p "Digite o alias: " alias
read -p "Digite o bitcoind.rpcuser: " bitcoind_rpcuser
read -p "Digite o bitcoind.rpcpass: " bitcoind_rpcpass
echo "AVISO: Salve a senha que você escolher para a carteira Lightning. Caso contrário, você pode perder seus fundos. A senha deve ter pelo menos 8 caracteres."
  while true; do
    read -p "Escolha uma senha para a carteira Lightning: " password
    echo
    if [ ${#password} -ge 8 ]; then
      break
    else
      echo "A senha deve ter pelo menos 8 caracteres. Tente novamente."
    fi
  done
    update_and_upgrade
    create_main_dir
    configure_ufw
    install_tor
    download_lnd
    configure_lnd
    create_lnd_service
    install_nodejs
    install_bos
    install_thunderhub
    install_lndg
    install_bitcoin
}

menu() {
  echo "Escolha uma opção:"
  echo "1) Instalação do BRLNBolt"
  echo "0) Sair"
  read -p "Opção: " option

  case $option in
    1)
      main
      ;;
    0)
      echo "Saindo..."
      exit 0
      ;;
    *)
      echo "Opção inválida!"
      ;;
  esac
}

menu
