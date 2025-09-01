# monoceros_simulations

- metrics generator
- simulation scripts

sh start_nodes.sh 1 10 r1 r1 0
sh start_nodes.sh 1 10 r2 r1 10
sh start_nodes.sh 1 10 r3 r2 20
sh start_nodes.sh 1 10 r4 r3 30
sh start_nodes.sh 1 10 r5 r4 40
sh start_nodes.sh 1 10 r6 r5 50
sh start_nodes.sh 1 10 r7 r6 60
sh start_nodes.sh 1 10 r8 r7 70
sh start_nodes.sh 1 10 r9 r8 80

bash start_nodes.sh 1 20 r1 r1 1000
bash start_nodes.sh 1 20 r2 r1 1020
bash start_nodes.sh 1 20 r3 r2 1040

helper commands
- print container logs to .log file
```shell
for name in $(docker ps --format '{{.Names}}'); do docker logs "$name" > "log/tmp_${name}.log"; done
```
- check current values
    docker logs r1_node_1 | grep 'total_app_memory_usage_bytes{global=\"y\"}'
    docker logs r3_node_1 | grep 'rank'

plotter - go run min.go 6001 6060
value extractor - go run min.go 6001 6060

sh stop_percent.sh 70 r1

Connect to the clusteer:

    ssh nova_cluster
    oarsub -I -l {"cluster='alakazam'"}/nodes=1,walltime=3:00
    oarsub -I -l nodes=8,walltime=3:00

wait time when root is deadc
- last + 2*Tagg - for region promotion
- prev + wait for first aggregation result to come - for rr promotion

docker stop r1_node_9 && echo "Stopped at: $(date +%s)"

scp -r nova_cluster:/home/tamara/monoceros_simulations/scripts/log ~/Documents/monitoring/impl/exported

CLUSTER EXPERIMENTS:

export OAR_JOB_ID={JOB_ID}
bash start_nodes_cluster.sh 100 2 50 150
bash cleanup_nodes_cluster.sh

check who was promoted as root:

docker ps --format '{{.Names}}' | xargs -I{} sh -c "echo '=== {} ==='; docker logs {} 2>&1 | grep 'still join rrn'"

resource usage:

top -bn1 | grep "Cpu(s)"
free -h