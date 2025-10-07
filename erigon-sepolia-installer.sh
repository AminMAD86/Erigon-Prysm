#!/bin/bash

# --- Colors ---
NC='\033[0m'
ORANGE='\033[38;5;208m'
RED='\033[31m'
CYAN='\033[36m'
GREEN='\033[32m'
GRAY='\033[90m'
SUCCESS=true

# --- Banner ---
clear
echo -e "${ORANGE}============================================================${NC}"
echo -e "${ORANGE} ETHEREUM SEPOLIA NODE INSTALLER (Erigon)${NC}"
echo -e "${ORANGE} Optimized for Screen + High Speed Downloads${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- System Check (Simplified) ---
echo -e "${ORANGE}Checking your system resources...${NC}"
AVAILABLE_SPACE=$(df -BG --output=avail . | tail -1 | tr -d 'G ')
MOUNT_POINT=$(df -h . | awk 'NR==2 {print $6}')
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -g | awk '/Mem:/ {print $2}')

echo "Your System Resources:"
echo "• Checked mount point: $MOUNT_POINT"
echo "• Available Storage: ${AVAILABLE_SPACE}G"
echo "• CPU Cores: ${CPU_CORES}"
echo "• Total RAM: ${TOTAL_RAM}GB"
echo -e "${GREEN}• Proceeding with installation...${NC}"
echo -e "${ORANGE}============================================================${NC}"

# --- Start Peak Storage Monitor ---
STORAGE_BEFORE=$(df -BG --output=used . | tail -1 | tr -d 'G ')
PEAK_STORAGE_FILE=$(mktemp)
echo "$STORAGE_BEFORE" > "$PEAK_STORAGE_FILE"

echo -e "${ORANGE}Starting peak storage monitor in the background...${NC}"
{
  PEAK_SO_FAR=$STORAGE_BEFORE
  while ps -p $$ > /dev/null; do
    CURRENT_USED=$(df -BG --output=used . | tail -1 | tr -d 'G ' || echo "$PEAK_SO_FAR")
    if (( CURRENT_USED > PEAK_SO_FAR )); then
      PEAK_SO_FAR=$CURRENT_USED
      echo "$PEAK_SO_FAR" > "$PEAK_STORAGE_FILE"
    fi
    sleep 2
  done
} &
MONITOR_PID=$!

echo -e "${ORANGE}============================================================${NC}"

# --- Prerequisites ---
echo -e "${ORANGE}Checking and installing prerequisites...${NC}"

# --- All apt-based tools (lz4, pv, ufw, wget) ---
echo -e "${CYAN}• Checking and installing required system tools...${NC}"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y >/dev/null 2>&1
  
  if ! command -v lz4 >/dev/null 2>&1; then
    sudo apt-get install -y lz4 >/dev/null 2>&1 || echo -e "${RED}• Failed to install lz4.${NC}"
  else
    echo "• lz4 already installed."
  fi
  
  if ! command -v pv >/dev/null 2>&1; then
    sudo apt-get install -y pv >/dev/null 2>&1 && echo "• 'pv' installed." || echo "• Could not install 'pv'. Progress bar may be omitted."
  else
    echo "• pv (for progress bar) already installed."
  fi
  
  if ! command -v ufw >/dev/null 2>&1; then
    sudo apt-get install -y ufw >/dev/null 2>&1 && echo "• 'ufw' installed." || echo -e "${RED}• Failed to install 'ufw'. Firewall setup will be skipped.${NC}"
  else
    echo "• ufw already installed."
  fi
  
  if ! command -v wget >/dev/null 2>&1; then
    sudo apt-get install -y wget >/dev/null 2>&1 || echo -e "${RED}• Failed to install wget.${NC}"
  else
    echo "• wget already installed."
  fi
  
  echo "• All apt-based prerequisites checked and installed."
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y epel-release >/dev/null 2>&1
  sudo yum install -y lz4 pv ufw wget >/dev/null 2>&1 && echo "• All yum-based prerequisites checked and installed." || echo -e "${RED}• Failed to install one or more system packages.${NC}"
fi

# --- Docker & Compose ---
if $SUCCESS; then
  echo -e "${ORANGE}Checking for Docker and Docker Compose...${NC}"
  if ! command -v docker >/dev/null 2>&1; then
    echo "• Docker not found. Installing prerequisites..."
    wget -qO- https://get.docker.com | bash >/dev/null 2>&1 || SUCCESS=false
  fi
  
  if ! sudo docker compose version >/dev/null 2>&1; then
    echo "• Docker Compose plugin not found. Installing prerequisites..."
    sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1 || SUCCESS=false
  fi
  
  if $SUCCESS; then
    echo "• Docker and Compose are installed."
  fi
fi

# --- Directory Structure ---
if $SUCCESS; then
  echo -e "${ORANGE}Creating directory structure...${NC}"
  mkdir -p ethereum/execution ethereum/consensus || { echo -e "${RED}Failed to create directories.${NC}" SUCCESS=false }
  if $SUCCESS; then
    echo "• Directory structure ready."
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Generate JWT Secret ---
if $SUCCESS; then
  echo -e "${ORANGE}Generating JWT secret...${NC}"
  if [ -f ethereum/jwt.hex ]; then
    echo "• JWT secret already exists, skipping."
  else
    openssl rand -hex 32 | tr -d "\n" > ethereum/jwt.hex || { echo -e "${RED}Failed to generate JWT secret.${NC}" SUCCESS=false }
    if $SUCCESS; then
      echo "• JWT secret created."
    fi
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Snapshot Section with High-Speed Download ---
if $SUCCESS; then
  echo -e "${ORANGE}Fetching latest Erigon snapshot for Sepolia...${NC}"
  
  # Try multiple snapshot sources for better reliability
  echo "• Checking available snapshot sources..."
  
  # Primary source: Erigon official snapshots
  SNAPSHOT_URL="https://snapshots.ethpandaops.io/sepolia/erigon/latest/snapshot.tar.lz4"
  
  # Test if primary URL works
  if ! wget --spider --timeout=10 "$SNAPSHOT_URL" 2>/dev/null; then
    echo "• Primary snapshot source unavailable, trying alternative..."
    # Alternative: Use a known working block number
    SNAPSHOT_URL="https://snapshots.ethpandaops.io/sepolia/erigon/9360000/snapshot.tar.lz4"
    
    if ! wget --spider --timeout=10 "$SNAPSHOT_URL" 2>/dev/null; then
      echo "• All snapshot sources unavailable, will sync from genesis instead"
      SNAPSHOT_URL=""
    fi
  fi
  
  if [ -n "$SNAPSHOT_URL" ]; then
    echo "• Using snapshot URL: $SNAPSHOT_URL"
  else
    echo "• No snapshot available, Erigon will sync from genesis (slower but reliable)"
  fi
  
  echo "• Getting snapshot size for progress bar..."
  SNAPSHOT_SIZE=$(wget --spider --server-response "$SNAPSHOT_URL" 2>&1 | grep -i 'content-length' | awk '{print $2}' | tr -d '\r')

  cd ethereum/execution || { echo -e "${RED}ERROR: ethereum/execution directory not found.${NC}" SUCCESS=false }
fi

if $SUCCESS && [ -n "$SNAPSHOT_URL" ]; then
  echo -e "${ORANGE}• Downloading and extracting snapshot (HIGH SPEED)...${NC}"
  rm -rf ./*

  # Optimize wget for maximum speed downloads
  WGET_OPTS="--timeout=60 --tries=5 --retry-connrefused --continue --progress=bar:force --no-check-certificate"
  
  if command -v pv >/dev/null 2>&1 && [ -n "$SNAPSHOT_SIZE" ]; then
    echo "• Snapshot size found. Starting MAXIMUM SPEED download with progress..."
    # Use optimized wget settings for speed
    wget $WGET_OPTS -O - "$SNAPSHOT_URL" | pv -pterb -s "$SNAPSHOT_SIZE" | lz4 -d | tar -xf - || SUCCESS=false
  elif command -v pv >/dev/null 2>&1; then
    echo "• Starting MAXIMUM SPEED download (size unknown)..."
    wget $WGET_OPTS -O - "$SNAPSHOT_URL" | pv | lz4 -d | tar -xf - || SUCCESS=false
  else
    echo "• Starting MAXIMUM SPEED download (no progress bar)..."
    wget $WGET_OPTS -O - "$SNAPSHOT_URL" | lz4 -d | tar -xf - || SUCCESS=false
  fi

  cd ../.. || true

  if $SUCCESS; then
    echo -e "${GREEN}Snapshot imported successfully.${NC}"
  else
    echo -e "${RED}ERROR: Snapshot download or extraction failed.${NC}"
    echo -e "${ORANGE}• Will continue with genesis sync instead...${NC}"
    SUCCESS=true  # Don't fail the entire script, just skip snapshot
  fi
elif $SUCCESS; then
  echo -e "${ORANGE}• Skipping snapshot download, will sync from genesis...${NC}"
  # Create minimal directory structure for genesis sync
  mkdir -p chaindata
  cd ../.. || true
fi

# --- Write Docker Compose File ---
if $SUCCESS; then
  echo -e "${ORANGE}Writing Docker Compose file...${NC}"
  cat > ethereum/docker-compose.yml <<'EOF'
services:
  erigon:
    image: erigontech/erigon:v3.2.0
    container_name: erigon
    restart: unless-stopped
    user: "0:0"
    network_mode: host
    volumes:
      - ./execution:/data
      - ./jwt.hex:/data/jwt.hex
    command:
      - --sepolia
      - --datadir=/data
      - --private.api.addr=0.0.0.0:9090
      - --http.api=eth,erigon,engine,net,debug,trace,web3
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.corsdomain=*
      - --http.vhosts=*
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/data/jwt.hex
      - --externalcl
      - --nat=extip:149.5.246.196
      - --p2p.allowed-ports=30303-30315
      - --prune.mode=full
      - --batchSize=1GB
      - --db.read.concurrency=8
      - --rpc.batch.concurrency=8
      - --sync.loop.block.limit=20000
      - --sync.loop.throttle=25ms
      - --bodies.cache=3GB
      - --state.cache=2GB
      - --private.api.ratelimit=31872
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  prysm:
    image: gcr.io/prysmaticlabs/prysm/beacon-chain:v5.3.2
    container_name: prysm
    restart: unless-stopped
    user: "0:0"
    network_mode: host
    volumes:
      - /root/ethereum/consensus:/data
      - /root/ethereum/jwt.hex:/data/jwt.hex
    ports:
      - 3500:3500
      - 4000:4000
      - 13000:13000
      - 12000:12000/udp
    command:
      - --sepolia
      - --datadir=/data
      - --execution-endpoint=http://127.0.0.1:8551
      - --jwt-secret=/data/jwt.hex
      - --rpc-host=0.0.0.0
      - --rpc-port=4000
      - --grpc-gateway-host=0.0.0.0
      - --grpc-gateway-port=3500
      - --grpc-gateway-corsdomain=*
      - --checkpoint-sync-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --genesis-beacon-api-url=https://checkpoint-sync.sepolia.ethpandaops.io
      - --p2p-tcp-port=13000
      - --p2p-udp-port=12000
      - --p2p-max-peers=128
      - --max-goroutines=4096
      - --enable-historical-state-representation
      - --blob-retention-epochs=4096
      - --enable-experimental-backfill
      - --verbosity=info
      - --accept-terms-of-use
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

  echo "• Docker Compose file created."
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Start Docker Containers ---
if $SUCCESS; then
  echo -e "${ORANGE}Starting Docker containers...${NC}"
  cd ethereum
  docker compose up -d || { echo -e "${RED}Failed to start Docker containers.${NC}" SUCCESS=false }
  cd ..
  
  if $SUCCESS; then
    echo "• Docker containers started successfully."
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Install Dozzle for Monitoring ---
if $SUCCESS; then
  echo -e "${ORANGE}Installing Dozzle for log monitoring...${NC}"
  if ! docker ps -a --format "table {{.Names}}" | grep -q "dozzle"; then
    docker run -d --name dozzle --restart unless-stopped -p 9999:8080 -v /var/run/docker.sock:/var/run/docker.sock amir20/dozzle:latest >/dev/null 2>&1 && echo "• Dozzle installed." || echo "• Failed to install Dozzle."
  else
    echo "• Dozzle container already exists, skipping."
  fi
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Firewall Setup ---
if $SUCCESS; then
  echo -e "${ORANGE}Configuring firewall rules...${NC}"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1
    ufw allow ssh >/dev/null 2>&1
    ufw allow 30303/tcp >/dev/null 2>&1
    ufw allow 30303/udp >/dev/null 2>&1
    ufw allow 12000/udp >/dev/null 2>&1
    ufw allow 13000/tcp >/dev/null 2>&1
    ufw allow 9999/tcp >/dev/null 2>&1
    ufw allow 8545/tcp >/dev/null 2>&1
    ufw allow 3500/tcp >/dev/null 2>&1
    ufw allow 4000/tcp >/dev/null 2>&1
    ufw allow 8080/tcp >/dev/null 2>&1
    ufw allow 8081/tcp >/dev/null 2>&1
    ufw deny from any to any port 8551 proto tcp >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    echo "• Base firewall rules configured."
  else
    echo "• UFW not installed. Skipping firewall setup."
  fi
fi

# --- Monitor Erigon Sync Progress (Screen Optimized) ---
if $SUCCESS; then
  monitor_erigon_sync() {
    echo ""
    echo -e "${CYAN}• The node is now syncing (Screen-optimized monitoring)${NC}"
    first_run=true
    while true; do
      trap 'echo -e "\n\n${ORANGE}Monitoring skipped by user. Continuing setup...${NC}\n"; return' INT
      
      if [ "$first_run" = false ]; then
        printf "\033[5A"
      fi
      first_run=false
      
      SYNC_STATUS=$(wget -qO- --header="Content-Type: application/json" --post-data='{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' "http://localhost:8545" 2>/dev/null)
      LATEST_FINISHED_LINE=$(docker logs erigon 2>/dev/null | grep "Finished stage" | tail -1)
      FINISHED_STAGE_TEXT="${GRAY}Waiting for first stage to finish...${NC}"
      
      if [ -n "$LATEST_FINISHED_LINE" ]; then
        CLEAN_FINISHED_LINE=$(echo "$LATEST_FINISHED_LINE" | sed -e 's/\x1b\[[0-9;]*m//g')
        PARSED_STAGE_INFO=$(echo "$CLEAN_FINISHED_LINE" | grep -o 'pipeline_stages=[^ ]*' | cut -d'=' -f2)
        PARSED_STAGE_NAME=$(echo "$CLEAN_FINISHED_LINE" | grep -o 'stage=[^ ]*' | cut -d'=' -f2)
        
        if [ -n "$PARSED_STAGE_INFO" ] && [ -n "$PARSED_STAGE_NAME" ]; then
          FINISHED_STAGE_TEXT=$(printf "${GREEN}%-7s (%s)${NC}" "$PARSED_STAGE_INFO" "$PARSED_STAGE_NAME")
        fi
      fi
      
      LATEST_RUNNING_LINE=$(docker logs erigon 2>/dev/null | grep -E "Executing stage|Committed stage progress" | tail -1)
      RUNNING_STAGE_TEXT="${GRAY}Initializing...${NC}"
      
      if [ -n "$LATEST_RUNNING_LINE" ]; then
        CLEAN_RUNNING_LINE=$(echo "$LATEST_RUNNING_LINE" | sed -e 's/\x1b\[[0-9;]*m//g')
        RUNNING_STAGE_INFO=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'pipeline_stages=[^ ]*' | cut -d'=' -f2)
        RUNNING_STAGE_NAME=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'stage=[^ ]*' | cut -d'=' -f2)
        RUNNING_STAGE_PCT=$(echo "$CLEAN_RUNNING_LINE" | grep -o 'stage_progress=[^ ]*' | cut -d'=' -f2)
        
        if [ -n "$RUNNING_STAGE_INFO" ] && [ -n "$RUNNING_STAGE_NAME" ]; then
          if [ -n "$RUNNING_STAGE_PCT" ]; then
            RUNNING_STAGE_TEXT=$(printf "${CYAN}%-7s (%s) | Progress: %s${NC}" "$RUNNING_STAGE_INFO" "$RUNNING_STAGE_NAME" "$RUNNING_STAGE_PCT")
          else
            RUNNING_STAGE_TEXT=$(printf "${CYAN}%-7s (%s)${NC}" "$RUNNING_STAGE_INFO" "$RUNNING_STAGE_NAME")
          fi
        fi
      fi
      
      if echo "$SYNC_STATUS" | grep -q '"result":false'; then
        echo -e "${ORANGE}==================== ERIGON SYNC STATUS =====================\033[K${NC}"
        echo -e "${GREEN}Synced - ✔️ Synced\033[K${NC}"
        echo -e "${GREEN}Finished Stage - All stages complete.\033[K${NC}"
        echo -e "${GREEN}Current Stage - Done.\033[K${NC}"
        echo -e "${ORANGE}============================================================\033[K${NC}"
        sleep 1
        break
      else
        echo -e "${ORANGE}==================== ERIGON SYNC STATUS =====================\033[K${NC}"
        echo -e "${CYAN}Synced - ⏳ In Progress...\033[K${NC}"
        echo -e "Finished Stage - $FINISHED_STAGE_TEXT\033[K"
        echo -e "Current Stage - $RUNNING_STAGE_TEXT\033[K"
        echo -e "${ORANGE}============================================================\033[K${NC}"
      fi
      
      sleep 5
    done
    trap - INT
    echo ""
  }
  
  monitor_erigon_sync
fi

# --- Storage Summary ---
if $SUCCESS; then
  kill "$MONITOR_PID" 2>/dev/null
  wait "$MONITOR_PID" 2>/dev/null || true
  PEAK_STORAGE_DURING_SETUP=$(cat "$PEAK_STORAGE_FILE")
  rm "$PEAK_STORAGE_FILE"
  STORAGE_AFTER=$(df -BG --output=used . | tail -1 | tr -d 'G ')
  
  if [ -n "$STORAGE_BEFORE" ] && [ -n "$PEAK_STORAGE_DURING_SETUP" ]; then
    echo -e "${ORANGE}============================================================${NC}"
    echo -e "${ORANGE} STORAGE SUMMARY${NC}"
    echo -e "${ORANGE}============================================================${NC}"
    printf "• Initial Storage Used: %s\n" "${STORAGE_BEFORE}G"
    printf "• Peaked Storage During Setup: ${CYAN}%s${NC}\n" "${PEAK_STORAGE_DURING_SETUP}G"
    printf "• Final Storage Used: %s\n" "${STORAGE_AFTER}G"
  fi
fi

# --- Node Status Display ---
if $SUCCESS; then
  echo -e "${ORANGE}============================================================${NC}"
  echo -e "${ORANGE}ETHEREUM SEPOLIA NODE STATUS (Erigon + Prysm)${NC}"
  echo -e "${ORANGE}============================================================${NC}"
  echo -e "${GREEN}Local (Aztec node on this VPS)${NC}"
  echo "• Sepolia RPC : ✔️ http://localhost:8545"
  echo "• Beacon RPC : ✔️ http://localhost:3500"
  echo -e "\n${GREEN}Remote (Aztec node on different VPS)${NC}"
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  echo "• Sepolia RPC : ✔️ http://$LOCAL_IP:8545"
  echo "• Beacon RPC : ✔️ http://$LOCAL_IP:3500"
  echo -e "\n${GREEN}Monitoring logs${NC}"
  echo "• Dozzle : ✔️ http://$LOCAL_IP:9999"
  echo -e "${ORANGE}============================================================${NC}"
fi

# --- Footer ---
if $SUCCESS; then
  echo -e "${ORANGE}SETUP COMPLETE - ERIGON + PRYSM FOR AZTEC${NC}"
  echo -e "${ORANGE}------------------------------------------------------------${NC}"
  echo "• Your Aztec sequencer node should now work!"
  echo "• Port 8080 is free for Aztec"
  echo "• Blob data is supported for Aztec"
  echo "• Optimized for high-speed downloads and screen usage"
  echo -e "${ORANGE}============================================================${NC}"
else
  echo -e "${RED}Installation did not complete successfully.${NC}"
  echo -e "${RED}Please resolve errors and rerun the script.${NC}"
fi

# Installation complete
