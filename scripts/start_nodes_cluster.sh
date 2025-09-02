#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <num_nodes> <num_regions> <intraregional_latency> <interregional_latency>"
  exit 1
fi

NODES="$1"
REGIONS="$2"
INTRA_LATENCY="$3"
INTER_LATENCY="$4"

export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

declare -A container_info  # key: container name, value: host,NODE_ID,RN_LISTEN_ADDR,GN_LISTEN_ADDR

add_ssh_hosts_for_job() {
    local job_id="$1"
    local frontend_host="$2"
    local ssh_config="$HOME/.ssh/config"
    local user_name="tamara"
    local proxy="tamara@nova_cluster"

    if [ -z "$job_id" ]; then
        echo "Error: job ID not provided"
        return 1
    fi

    if [ -z "$frontend_host" ]; then
        echo "Error: FRONTEND_HOSTNAME is not set"
        return 1
    fi

    # Get assigned_hostnames remotely
    local host_line
    host_line=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$frontend_host" \
        "oarstat -f nodename -j $job_id" 2>/dev/null | grep 'assigned_hostnames' || true)

    if [ -z "$host_line" ]; then
        echo "No assigned hostnames found for job $job_id"
        return 0
    fi

    local hostnames
    hostnames=$(echo "$host_line" | awk -F'= ' '{print $2}' | tr '+' '\n')

    while read -r host; do
        [ -z "$host" ] && continue
        if ! grep -q "Host $host" "$ssh_config"; then
            echo -e "\nHost $host\n    User $user_name\n    ProxyJump $proxy" >> "$ssh_config"
            echo "Added $host to $ssh_config"
        else
            echo "$host already exists in $ssh_config"
        fi
    done <<< "$hostnames"
}

select_random_container() {
    local prefix="$1"
    local fallback_node_id="$2"
    local fallback_gn="$3"
    local fallback_rn="$4"

    local keys=("${!container_info[@]}")
    local matches=()

    for key in "${keys[@]}"; do
        if [[ "$key" == "$prefix"* ]]; then
            matches+=("$key")
        fi
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo "NODE_ID=$fallback_node_id"
        echo "GN_LISTEN_ADDR=$fallback_gn"
        echo "RN_LISTEN_ADDR=$fallback_rn"
        return 0
    fi

    local rand_index=$(( RANDOM % ${#matches[@]} ))
    local selected="${matches[$rand_index]}"
    IFS=',' read -r selected_host NODE_ID RN_LISTEN_ADDR GN_LISTEN_ADDR <<< "${container_info[$selected]}"

    echo "NODE_ID=$NODE_ID"
    echo "RN_LISTEN_ADDR=$RN_LISTEN_ADDR"
    echo "GN_LISTEN_ADDR=$GN_LISTEN_ADDR"
}

# Make sure $OAR_JOB_ID is set
if [ -z "${OAR_JOB_ID:-}" ]; then
    echo "Error: OAR_JOB_ID is not set"
    exit 1
fi

# Add SSH hosts for the job
add_ssh_hosts_for_job "$OAR_JOB_ID" "$FRONTEND_HOSTNAME"

# Generate latency
cd ../latency
rm -f latency.txt
go run main.go "$NODES" "$INTRA_LATENCY" "$REGIONS" "$INTER_LATENCY"
oar-p2p net up --addresses "$NODES" --latency-matrix latency.txt

# Get unique hostnames from oar-p2p net show
OUTPUT=$(oar-p2p net show)
HOSTNAMES=$(echo "$OUTPUT" | awk '{print $1}' | sort -u)

USER="tamara"
JUMP_HOST="tamara@nova_cluster"
IMAGE="monoceros-all"

# Build Docker images on each host
for host in $HOSTNAMES; do
    echo "Setting up $host"
    ssh "$host" bash -s <<EOF
cd hyparview && git pull
cd ../plumtree && git pull
cd ../monoceros && git pull
cd ../
docker build -t "$IMAGE" -f monoceros_simulations/Dockerfile .
EOF
done

per_region=$((NODES / REGIONS))

NET_SHOW_LINES=()
while IFS= read -r line; do
    NET_SHOW_LINES+=("$line")
done < <(oar-p2p net show)

# Start containers
# problem je to sto se startuju o nepravilnom redosledu, retry on join dok ne uspe?
declare -A host_cmds
for ((i=0; i<NODES; i++)); do
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

    line="${NET_SHOW_LINES[$i]}"
    MACHINE=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    HTTP_LA="${IP}:5001"
    RN_LA="${IP}:6001"
    GN_LA="${IP}:7001"
    RRN_LA="${IP}:8001"

    # Select RN and GN containers
    result=$(select_random_container "$REGION" "$NAME" "$GN_LA" "$RN_LA")
    eval "$result"
    RN_CONTACT_NODE_ID="$NODE_ID"
    RN_CONTACT_NODE_ADDR="$RN_LISTEN_ADDR"
    result=$(select_random_container "$GN_REGION" "$NAME" "$GN_LA" "$RN_LA")
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

    host_cmds["$MACHINE"]+=$(cat <<EOF

cd ./monoceros_simulations/scripts
rm -rf "$LOG"
mkdir -p "$LOG/results"
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
    -v "/home/tamara/monoceros_simulations/scripts/${LOG}:/var/log/monoceros" \
    -v "/home/tamara/signal:/var/log/signal" \
    "$IMAGE"
cd ../../
sleep 0.3

EOF
)
    container_info["$NAME"]="$MACHINE,$NAME,$RN_LA,$GN_LA"
done

# now execute per host
for host in $HOSTNAMES; do
    echo "Starting containers on $host..."
    ssh "$host" bash -s <<< "${host_cmds[$host]}"
    sleep 0.3
done

for hsot in $HOSTNAMES; do
    echo "Signaling nodes to start ..."
    ssh "$host" touch /home/tamara/signal/start
    # break
done