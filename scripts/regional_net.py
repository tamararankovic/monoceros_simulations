import json
import networkx as nx
import os
import sys

# --- Load JSON ---
with open("all_states.json", "r") as f:
    states = json.load(f)

# --- HyParView graph ---
G = nx.DiGraph()
for node in states:
    node_id = node.get("ID")
    if not node_id:
        continue
    G.add_node(node_id)

    active_view = node.get("RegionalNetwork", {}).get("Plumtree", {}).get("HyParViewState", {}).get("ActiveView", [])
    for peer_id in active_view:
        G.add_edge(node_id, peer_id)

# Count connected components
# Since it's a directed graph, we need to use weakly connected components
# (ignoring edge direction) or strongly connected components
weakly_connected_components = list(nx.weakly_connected_components(G))
# strongly_connected_components = list(nx.strongly_connected_components(G))

print(f"Number of weakly connected components: {len(weakly_connected_components)}")
# print(f"Number of strongly connected components: {len(strongly_connected_components)}")

if len(sys.argv) < 2:
    exit(0)

# # Print sizes of each component
# print("\nWeakly connected component sizes:")
# for i, component in enumerate(weakly_connected_components):
#     print(f"Component {i+1}: {len(component)} nodes")

# print("\nStrongly connected component sizes:")
# for i, component in enumerate(strongly_connected_components):
#     print(f"Component {i+1}: {len(component)} nodes")

dot_file = "graphs/hyparview_graph.dot"
nx.nx_agraph.write_dot(G, dot_file)
os.system(f"sfdp -Tpng {dot_file} -Gsize=20,20 -Gdpi=150 -o graphs/hyparview_graph.png")

print("\nHyParView graph rendered as hyparview_graph.png")

# # --- Plumtree graphs (per tree ID) ---
# # Dictionary: tree_id -> graph
# tree_graphs = {}

# for node in states:
#     node_id = node.get("ID")
#     if not node_id:
#         continue

#     trees = node.get("RegionalNetwork", {}).get("Plumtree", {}).get("Trees", [])
#     for tree in trees:
#         tree_id = tree.get("ID")
#         if not tree_id:
#             continue

#         # Create graph if new
#         if tree_id not in tree_graphs:
#             tree_graphs[tree_id] = nx.DiGraph()

#         tree_graphs[tree_id].add_node(node_id)

#         # Add edges to EagerPeers
#         eager_peers = tree.get("EagerPeers", [])
#         for peer_id in eager_peers:
#             tree_graphs[tree_id].add_edge(node_id, peer_id)

# # --- Export each tree graph ---
# for tree_id, graph in tree_graphs.items():
#     dot_file = f"graphs/plumtree_{tree_id}.dot"
#     png_file = f"graphs/plumtree_{tree_id}.png"

#     nx.nx_agraph.write_dot(graph, dot_file)
#     exit_code = os.system(f"sfdp -Tpng {dot_file} -Gsize=20,20 -Gdpi=150 -o {png_file}")
#     if exit_code == 0:
#         print(f"Plumtree graph for tree {tree_id} rendered as {png_file}")
#     else:
#         print(f"Error rendering tree {tree_id}")
