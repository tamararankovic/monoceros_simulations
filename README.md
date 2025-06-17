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

sh start_nodes.sh 1 10 r1 r1 0
sh start_nodes.sh 1 30 r2 r1 10
sh start_nodes.sh 1 30 r3 r2 40

helper commands
- print container logs to .log file
    for name in $(docker ps --format '{{.Names}}'); do docker logs "$name" > "log/tmp_${name}.log"; done
- check current values
    docker logs r3_node_1 | grep 'total_app_memory_usage_bytes{'
    docker logs r3_node_1 | grep 'rank'