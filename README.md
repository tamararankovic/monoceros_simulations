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
    oarsub -I -l {"cluster='moltres'"}/nodes=1,walltime=2:30

wait time when root is dead
- last + 2*Tagg - for region promotion
- prev + wait for first aggregation result to come - for rr promotion

docker stop r1_node_9 && echo "Stopped at: $(date +%s)"