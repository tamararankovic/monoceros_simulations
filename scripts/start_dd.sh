#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <num_nodes> <num_regions> <intraregional_latency> <interregional_latency> <exp_name>"
  exit 1
fi

NODES="$1"
REGIONS="$2"
INTRA_LATENCY="$3"
INTER_LATENCY="$4"
EXP_NAME="$5"

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

declare -A container_info  # key: container name, value: host,NODE_ID,RN_LISTEN_ADDR,GN_LISTEN_ADDR

select_random_container() {
    local prefix="$1"
    local fallback_node_id="$2"
    local fallback_addr="$3"

    local keys=("${!container_info[@]}")
    local matches=()

    for key in "${keys[@]}"; do
        if [[ "$key" == "$prefix"* ]]; then
            matches+=("$key")
        fi
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "NODE_ID=$fallback_node_id"
        echo "LISTEN_ADDR=$fallback_addr"
        return 0
    fi

    local rand_index=$(( RANDOM % ${#matches[@]} ))
    local selected="${matches[$rand_index]}"
    IFS=',' read -r selected_host NODE_ID LISTEN_ADDR <<< "${container_info[$selected]}"

    echo "NODE_ID=$NODE_ID"
    echo "LISTEN_ADDR=$LISTEN_ADDR"
}

# Get unique hostnames from oar-p2p net show
OUTPUT=$(oar-p2p net show)
HOSTNAMES=$(echo "$OUTPUT" | awk '{print $1}' | sort -u)

IMAGE="digest-diffusion"

# Build Docker images on each host
for host in $HOSTNAMES; do
    echo "Setting up $host"
    ssh "$host" bash -s <<EOF
cd hyparview && git pull
cd ../digest_diffusion && git pull
cd ../
docker build -t "$IMAGE" -f digest_diffusion/Dockerfile .
EOF
done

per_region=$((NODES / REGIONS))

NET_SHOW_LINES=()
while IFS= read -r line; do
    NET_SHOW_LINES+=("$line")
done < <(oar-p2p net show)

# Start containers
declare -A host_cmds
for ((i=0; i<NODES; i++)); do
    REGION_NUM=$(((i / per_region)+1))
    REGION="r${REGION_NUM}"
    REGION_IDX=$(((i % per_region)+1))
    NAME="${REGION}_node_$REGION_IDX"

    line="${NET_SHOW_LINES[$i]}"
    MACHINE=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    LA="${IP}:6001"

    # Select contact node
    result=$(select_random_container "$REGION" "$NAME" "$LA")
    eval "$result"
    CONTACT_NODE_ID="$NODE_ID"
    CONTACT_NODE_ADDR="$LISTEN_ADDR"

    LOG="/home/tamara/experiments/results/${EXP_NAME}/${NAME}"

    echo "Node ID: ${NAME}"
    echo "Region: ${REGION}"
    echo "IP address: ${IP}"
    echo "Listen addr: ${LA}"
    echo "Contact node ID: ${CONTACT_NODE_ID}"
    echo "Contact node addr: ${CONTACT_NODE_ADDR}"

    host_cmds["$MACHINE"]+=$(cat <<EOF

cd ./monoceros_simulations/scripts
rm -rf "$LOG"
mkdir -p "$LOG/results"
docker run -dit \
    --memory 250m \
    --name "$NAME" \
    --network=host \
    --env-file "dd.env" \
    -e NODE_REGION="$REGION" \
    -e NODE_ID="$NAME" \
    -e CONTACT_NODE_ID="$CONTACT_NODE_ID" \
    -e CONTACT_NODE_ADDR="$CONTACT_NODE_ADDR" \
    -e LISTEN_ADDR="$LA" \
    -v "${LOG}:/var/log/dd" \
    "$IMAGE"
cd ../../
sleep 0.3

EOF
)
    container_info["$NAME"]="$MACHINE,$NAME,$LA"
done

# now execute per host
for host in $HOSTNAMES; do
    echo "Starting containers on $host..."
    ssh "$host" bash -s <<< "${host_cmds[$host]}"
    sleep 0.3
done