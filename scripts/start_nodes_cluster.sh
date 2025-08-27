#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <num_nodes> <num_regions> <intraregional_latency> <interregional_latency>"
  exit 1
fi

add_ssh_config() {
    local host="$1"
    local user="$2"
    local jump="$3"
    local config="$HOME/.ssh/config"

    # check if "Host {host}" already exists
    if ! grep -q -E "^Host[[:space:]]+$host\$" "$config"; then
        {
            echo ""
            echo "Host $host"
            echo "    User $user"
            echo "    ProxyJump $jump"
        } >> "$config"
        echo "Added ssh config for $host"
    else
        echo "ssh config for $host already exists, skipping"
    fi
}

select_random_container() {
    local hostnames=($1)
    local prefix="$2"
    local fallback_node_id="$3"
    local fallback_gn="$4"
    local fallback_rn="$5"
    local -a containers=()
    local -a hosts=()

    # Collect all containers matching the prefix
    for host in "${hostnames[@]}"; do
        while read -r cname; do
            containers+=("$cname")
            hosts+=("$host")
        done < <(ssh "$host" "docker ps --format '{{.Names}}' | grep '^$prefix' || true")
    done

    # Fallback if no containers found
    if [ ${#containers[@]} -eq 0 ]; then
        echo "NODE_ID=$fallback_node_id"
        echo "GN_LISTEN_ADDR=$fallback_gn"
        echo "RN_LISTEN_ADDR=$fallback_rn"
        return 0
    fi

    # Pick a random container
    local rand_index=$(( RANDOM % ${#containers[@]} ))
    local selected_container="${containers[$rand_index]}"
    local selected_host="${hosts[$rand_index]}"

    # Retrieve environment variables inside the container
    ssh "$selected_host" "docker exec '$selected_container' env | grep -E '^(NODE_ID|GN_LISTEN_ADDR|RN_LISTEN_ADDR)='"
}

NODES="$1"
REGIONS="$2"
INTRA_LATENCY="$3"
INTER_LATENCY="$4"
export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

cd ../latency
rm latency.txt
go run main.go $NODES $INTRA_LATENCY $REGIONS $INTER_LATENCY
oar-p2p net up --addresses $NODES --latency-matrix latency.txt

OUTPUT=$(oar-p2p net show)
HOSTNAMES=$(echo "$OUTPUT" | awk '{print $1}' | sort -u)

USER="tamara"
JUMP_HOST="tamara@nova_cluster"
IMAGE="monoceros-all"

for host in $HOSTNAMES; do
    add_ssh_config "$host" "$USER" "$JUMP_HOST"
    ssh "$host" bash -s <<EOF
cd hyparview
git pull
cd ../plumtree
git pull
cd ../monoceros
git pull
cd ../
docker build -t "$IMAGE" -f monoceros_simulations/Dockerfile .
EOF
done

per_region=$((NODES / REGIONS))

for ((i=0; i<NODES; i++)); do
    # determine node region, region to contact in the global network, and name
    REGION_NUM=$(((i / per_region)+1))
    if (( REGION_NUM == 1 )); then
        GN_REGION_NUM=1
    else
        GN_REGION_NUM=$(( 1 + RANDOM % (REGION_NUM - 1) ))
    fi
    REGION="r${REGION_NUM}"
    GN_REGION="r${GN_REGION_NUM}"
    REGION_IDX=$(((i % per_region)+1))
    NAME="${REGION}_node_$REGION_IDX"

    # listen and connect sockets
    line_num=$((i+1))
    line=$(oar-p2p net show | sed -n "${line_num}p")
    MACHINE=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    HTTP_LA="${IP}:5001"
    RN_LA="${IP}:6001"
    GN_LA="${IP}:7001"
    RRN_LA="${IP}:8001"

    result=$(select_random_container "$HOSTNAMES" "$REGION" "$NAME" "$GN_LA", "$RN_LA")
    eval "$result"
    RN_CONTACT_NODE_ID="$NODE_ID"
    RN_CONTACT_NODE_ADDR="$RN_LISTEN_ADDR"
    result=$(select_random_container "$HOSTNAMES" "$GN_REGION" "$NAME" "$GN_LA", "$RN_LA")
    eval "$result"
    GN_CONTACT_NODE_ID="$NODE_ID"
    GN_CONTACT_NODE_ADDR="$GN_LISTEN_ADDR"
    
    LOG="log/${NAME}"

    echo "Node ID: ${NAME}"
    echo "Region: ${REGION}"
    echo "Global network region: ${GN_REGION}"
    echo "IP address: ${IP}"
    echo "HTTP listen addr: ${HTTP_LA}"
    echo "RN listen addr: ${RN_LA}"
    echo "RRN listen addr: ${RRN_LA}"
    echo "GN listen addr: ${GN_LA}"
    echo "RN contact node ID: ${RN_CONTACT_NODE_ID}"
    echo "RN contact node addr: ${RN_CONTACT_NODE_ADDR}"
    echo "GN contact node ID: ${GN_CONTACT_NODE_ID}"
    echo "GN contact node addr: ${GN_CONTACT_NODE_ADDR}"

    ssh "$MACHINE" bash -s <<EOF
cd ./monoceros_simulations/scripts
pwd
rm -rf $LOG
mkdir -p $LOG/results
docker run -dit \
    --name "$NAME" \
    --network=host \
    --env-file ".env" \
    -e NODE_REGION="$REGION" \
    -e NODE_ID="$NAME" \
    -e RN_CONTACT_NODE_ID="$RN_CONTACT_NODE_ID" \
    -e RN_CONTACT_NODE_ADDR="$RN_CONTACT_NODE_ADDR" \
    -e GN_CONTACT_NODE_ID="$GN_CONTACT_NODE_ID" \
    -e GN_CONTACT_NODE_ADDR="$GN_CONTACT_NODE_ADDR" \
    -e HTTP_SERVER_ADDR="$HTTP_LA" \
    -e RN_LISTEN_ADDR="$RN_LA" \
    -e GN_LISTEN_ADDR="$GN_LA" \
    -e RRN_LISTEN_ADDR="$RRN_LA" \
    -v "$(pwd)/${LOG}:/var/log/monoceros" \
    "$IMAGE"
EOF

    sleep 0.5
done