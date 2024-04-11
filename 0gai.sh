#!/bin/bash

set -e

# path sekrip
SCRIPT_PATH="$HOME/0gai.sh"

# Install node
function install_node() {

    if command -v node > /dev/null 2>&1; then
        echo "Node.js terinstall"
    else
        echo "Node.js Lagi di install，sabar..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm terinstall"
    else
        echo "npm Lagi di install，sabar..."
        sudo apt-get install -y npm
    fi

	# install PM2
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 terinstall"
    else
        echo "PM2 Lagi di install，sabar...."
        npm install pm2@latest -g
    fi

	# update sistem
	sudo apt update && sudo apt install -y curl git wget htop tmux build-essential jq make lz4 gcc unzip liblz4-tool clang cmake build-essential screen cargo

    # install Go
    sudo rm -rf /usr/local/go
    curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    source $HOME/.bash_profile

    # install 0g
    git clone https://github.com/0glabs/0g-evmos.git
    cd 0g-evmos
    git checkout v1.0.0-testnet
    make install
    evmosd version

	# simpan variabel
    read -r -p "Moniker: " NODE_MONIKER
    export NODE_MONIKER=$NODE_MONIKER
    # data moniker
    echo 'export MONIKER="$NODE_MONIKER"' >> ~/.bash_profile
    # data wallet, bebas
    #echo 'export WALLET_NAME="wallet"' >> ~/.bash_profile

    source $HOME/.bash_profile

    # inisiasi
    cd $HOME
    evmosd init $NODE_MONIKER --chain-id zgtendermint_9000-1
    evmosd config chain-id zgtendermint_9000-1
    evmosd config node tcp://localhost:26657
    evmosd config keyring-backend os 

    # install genesis
    wget https://github.com/0glabs/0g-evmos/releases/download/v1.0.0-testnet/genesis.json -O $HOME/.evmosd/config/genesis.json

    # set peers
    PEERS="1248487ea585730cdf5d3c32e0c2a43ad0cda973@peer-zero-gravity-testnet.trusted-point.com:26326" && \
    SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656" && \
    sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml

    # set gas
    sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml

    # start PM2
    pm2 start evmosd -- start && pm2 save && pm2 startup

    # stop Pm2
    pm2 stop evmosd

    # update snapshot data
    wget https://rpc-zero-gravity-testnet.trusted-point.com/latest_snapshot.tar.lz4

    # buat backup validator
    cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup

    # reset file
    evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book

    # ekstrak file
    lz4 -d -c ./latest_snapshot.tar.lz4 | tar -xf - -C $HOME/.evmosd

    # backup file
    mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json

    # start node
    pm2 start evmosd -- start
    pm2 logs evmosd

    # log
    evmosd status | jq .SyncInfo
    echo '==================== Selesai ========================='

}

# cek status
function check_service_status() {
    pm2 list
}

# log data
function view_logs() {
    pm2 logs evmosd
}

# uninstall node
function uninstall_node() {
    echo "yakin ingin uninstall dan hapus semua data?. [Y/N]"
    read -r -p "Konfirmasi: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "Sedang menghapus..."
            pm2 stop evmosd && pm2 delete evmosd
            rm -rf $HOME/.evmosd $HOME/evmos $(which evmosd)
            echo "Selsai."
            ;;
        *)
            echo "Batal"
            ;;
    esac
}

# buat wallet
function add_wallet() {
	read -p "Nama Wallet: " wallet_name
    evmosd keys add "$wallet_name"
    echo "Wallet, isi kan faucet: "
    echo "0x$(evmosd debug addr $(evmosd keys show $wallet_name -a) | grep hex | awk '{print $3}')"
}

# import wallet
function import_wallet() {
	read -p "Nama wallet: " wallet_name
    evmosd keys add "$wallet_name" --recover
}

# cek saldo
function check_balances() {
    read -p "Alamat Wallet: " wallet_address
    evmosd query bank balances "$wallet_address" 
}

# cek status
function check_sync_status() {
    evmosd status 2>&1 | jq .SyncInfo
}

# buat validator
function add_validator() {
	
	read -p "Nama wallet: " wallet_name
	read -p "Moniker: " validator_name
	
	evmosd tx staking create-validator \
	  --amount=10000000000000000aevmos \
	  --pubkey=$(evmosd tendermint show-validator) \
	  --moniker=$validator_name \
	  --chain-id=zgtendermint_9000-1 \
	  --commission-rate=0.05 \
	  --commission-max-rate=0.10 \
	  --commission-max-change-rate=0.01 \
	  --min-self-delegation=1 \
	  --from=$wallet_name \
	  --identity="" \
	  --website="" \
	  --details="kulicapital nodeteam" \
	  --gas=500000 \
	  --gas-prices=99999aevmos \
	  -y

}

function stop_node(){
	pm2 stop evmosd
}

function start_node(){
	pm2 start evmosd -- start
}

function install_storage_node() {
 
	# anbil storage
	git clone https://github.com/0glabs/0g-storage-node.git
	
	#ke folder
	cd 0g-storage-node
	git submodule update --init
	
	# eksekusi
	cargo build --release
	
	#buat screen
	cd run
	screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
	echo '==================== Selesai ========================='
	
}

function stop_storage_node(){
	screen -S zgs_node_session -X quit
}

function start_storage_node(){
	cd 0g-storage-node/run
	screen -dmS zgs_node_session ../target/release/zgs_node --config config.toml
}

function view_storage_logs(){
	current_date=$(date +%Y-%m-%d)
	tail -f $HOME/0g-storage-node/run/log/zgs.log.$current_date
}

# menu
function main_menu() {
        clear
        echo "==============Min Spek=============="
    	echo "8 GB RAM"
    	echo "CPU: 4 cores"
        echo "Disk: 500 GB SSD"
        echo "-----------Menu Validator------------"
        echo "1. Install validator"
        echo "2. Tambah Wallet"
        echo "3. Import Wallet"
        echo "4. Cek Saldo"
        echo "5. Buat Validator"
        echo "6. Cek status validator"
        echo "7. Cek sinkronisasi"
        echo "8. lihat node log"
        echo "9. Stop node"
        echo "10. Start node"
        echo "-------------Menu Storage-------------"
        echo "11. Install storage node"
        echo "12. lihat node log"
        echo "13. Stop node"
        echo "14. Start node"
        echo "---------------MenuLain---------------"
        echo "15. Hapus Node"
        echo "0. Keluar"
        read -p "Pilih: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) add_validator ;;
        6) check_service_status ;;
        7) check_sync_status ;;
        8) view_logs ;;
        9) stop_node ;;
        10) start_node ;;
        11) install_storage_node ;;
        12) view_storage_logs ;;
        13) stop_storage_node ;;
        14) start_storage_node ;;
        15) uninstall_node ;;
        0) echo "Terkeluar"; exit 0 ;;
	    *) echo "Pilihan tidak valid"; sleep 3 ;;
	    esac
}

# ke menu utama
main_menu