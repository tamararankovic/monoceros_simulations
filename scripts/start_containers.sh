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

declare -A container_info
declare -A container_ips

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

# Get hostnames
OUTPUT=$(oar-p2p net show)
HOSTNAMES=$(echo "$OUTPUT" | awk '{print $1}' | sort -u)
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

# Read container IPs and host assignments
NET_SHOW_LINES=()
while IFS= read -r line; do
    NET_SHOW_LINES+=("$line")
done < <(oar-p2p net show)

# Start containers and collect info
declare -A host_cmds
for ((i=0; i<NODES; i++)); do
    REGION_NUM=$(((i / per_region)+1))
    GN_REGION_NUM=$(( REGION_NUM == 1 ? 1 : 1 + RANDOM % (REGION_NUM - 1) ))
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

    # Select RN and GN contact nodes
    result=$(select_random_container "$REGION" "$NAME" "$GN_LA" "$RN_LA")
    eval "$result"
    RN_CONTACT_NODE_ID="$NODE_ID"
    RN_CONTACT_NODE_ADDR="$RN_LISTEN_ADDR"
    result=$(select_random_container "$GN_REGION" "$NAME" "$GN_LA" "$RN_LA")
    eval "$result"
    GN_CONTACT_NODE_ID="$NODE_ID"
    GN_CONTACT_NODE_ADDR="$GN_LISTEN_ADDR"

    LOG="/home/tamara/experiments/results/${EXP_NAME}/${NAME}"

    host_cmds["$MACHINE"]+=$(cat <<EOF

cd ./monoceros_simulations/scripts
rm -rf "$LOG"
mkdir -p "$LOG/results"
docker run -dit \
    --memory 250m \
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
    -v "${LOG}:/var/log/monoceros" \
    "$IMAGE"
cd ../../
sleep 0.3

EOF
)

    container_info["$NAME"]="$MACHINE,$NAME,$RN_LA,$GN_LA"
    container_ips["$NAME"]="$IP"
done

# Start containers per host
for host in $HOSTNAMES; do
    echo "Starting containers on $host..."
    ssh "$host" bash -s <<< "${host_cmds[$host]}"
    sleep 0.3
done

# # Apply Gaussian-distributed packet loss per IP pair across all hosts
# for host in $HOSTNAMES; do
#     echo "Preparing packet loss commands for $host..."

#     # Find all containers on this host
#     host_containers=()
#     for c in "${!container_info[@]}"; do
#         IFS=',' read -r c_host _ _ _ <<< "${container_info[$c]}"
#         [[ "$c_host" == "$host" ]] && host_containers+=("$c")
#     done

#     if [[ ${#host_containers[@]} -eq 0 ]]; then
#         echo "No containers on $host, skipping"
#         continue
#     fi

#     # Detect host interface from first container's IP
#     first_ip="${container_ips[${host_containers[0]}]}"
#     iface=$(ssh "$host" "ip route get $first_ip | awk '{for(i=1;i<=NF;i++){if(\$i==\"dev\") print \$(i+1)}}' | head -n1")
#     if [[ -z "$iface" ]]; then
#         echo "Could not detect interface on $host, skipping"
#         continue
#     fi

#     # Prepare all commands for this host
#     cmds="tc qdisc del dev $iface root 2>/dev/null; tc qdisc add dev $iface root handle 1: prio;"

#     for src_name in "${host_containers[@]}"; do
#         src_ip="${container_ips[$src_name]}"

#         for dst_name in "${!container_ips[@]}"; do
#             [[ "$src_name" == "$dst_name" ]] && continue
#             dst_ip="${container_ips[$dst_name]}"

#             # Gaussian sample with mean=5%, stddev=5%, clipped 0-100%
#             loss=$(awk 'BEGIN{srand(); mu=5; sigma=5;
#                           x=mu+sigma*sqrt(-2*log(rand()))*cos(2*3.1415926535*rand());
#                           if(x<0)x=0; if(x>100)x=100; printf "%.2f", x}')

#             handle=$(( 10 + RANDOM % 90 ))

#             cmds+="tc qdisc add dev $iface parent 1:${handle} handle ${handle}: netem loss ${loss}%;"
#             cmds+="tc filter add dev $iface protocol ip parent 1:0 prio ${handle} u32 match ip src ${src_ip} match ip dst ${dst_ip} flowid 1:${handle};"
#         done
#     done

#     # Execute all commands in a single SSH call
#     ssh "$host" bash -c "$cmds"
#     echo "Packet loss configured on $host ($iface)"
# done


# echo "All containers started and random per-IP-pair packet loss configured."
