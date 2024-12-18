#!/bin/bash

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
                                  -conf=/home/admin/.bitcoin/bitcoin.conf \
                                  -datadir=/home/admin/.bitcoin \
                                  -startupnotify="chmod g+r /home/admin/.bitcoin/.cookie"
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
