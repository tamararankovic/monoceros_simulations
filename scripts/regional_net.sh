export FRONTEND_HOSTNAME=nova_cluster
export HOSTNAME=tamara

#!/usr/bin/env bash
set -euo pipefail

OUTPUT=$(oar-p2p net show)
HOSTNAMES=$(echo "$OUTPUT" | awk '{print $1}' | sort -u)

# File to store all JSONs in current directory
JSON_FILE="./all_states.json"
# Initialize empty file
> "$JSON_FILE"

for host in $HOSTNAMES; do
    echo "Processing host: $host"

    # Run everything inside one SSH session per host
    ssh "$host" bash -c "'
        for c in \$(docker ps --format \"{{.Names}}\"); do
            # Get first HTTP_* env var
            env_ip=\$(docker inspect -f \"{{range .Config.Env}}{{println .}}{{end}}\" \$c | grep \"^HTTP_\" | head -n1 || true)
            if [[ -n \"\$env_ip\" ]]; then
                ip_port=\${env_ip#*=}
                ip=\${ip_port%%:*}
                echo \"Fetching state from \$ip:5001\" >&2
                curl -s \"http://\$ip:5001/state\"
            fi
        done
    '" >> "$JSON_FILE"
done

# Optional: wrap multiple JSON objects into a proper JSON array
jq -s '.' "$JSON_FILE" > tmp && mv tmp "$JSON_FILE"

echo "All states collected in $JSON_FILE"
