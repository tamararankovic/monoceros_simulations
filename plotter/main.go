package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/dominikbraun/graph"
	"github.com/dominikbraun/graph/draw"
)

type State struct {
	ID              string          `json:"Id"`
	RegionalNetwork RegionalNetwork `json:"RegionalNetwork"`
}

type RegionalNetwork struct {
	Plumtree Plumtree `json:"Plumtree"`
}

type Plumtree struct {
	Trees []Tree `json:"Trees"`
}

type Tree struct {
	ID         string   `json:"ID"`
	Parent     string   `json:"Parent"`
	EagerPeers []string `json:"EagerPeers"`
	LazyPeers  []string `json:"LazyPeers"`
	Destroyed  bool     `json:"Destroyed"`
}

func main() {
	if len(os.Args) != 3 {
		log.Fatalf("Usage: %s <startPort> <endPort>", os.Args[0])
	}

	startPort, err := strconv.Atoi(os.Args[1])
	if err != nil {
		log.Fatalf("Invalid start port: %v", err)
	}
	endPort, err := strconv.Atoi(os.Args[2])
	if err != nil {
		log.Fatalf("Invalid end port: %v", err)
	}

	treeGraphs := make(map[string]graph.Graph[string, string])

	for port := startPort; port <= endPort; port++ {
		url := fmt.Sprintf("http://localhost:%d/state", port)
		resp, err := http.Get(url)
		if err != nil {
			log.Printf("Failed to get %s: %v", url, err)
			continue
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			log.Printf("Failed to read response body: %v", err)
			continue
		}

		var state State
		if err := json.Unmarshal(body, &state); err != nil {
			log.Printf("Failed to parse JSON from %s: %v", url, err)
			continue
		}

		nodeID := state.ID

		for _, tree := range state.RegionalNetwork.Plumtree.Trees {
			treeID := tree.ID
			// if tree.Destroyed {
			// 	continue // Skip destroyed trees
			// }

			g, exists := treeGraphs[treeID]
			if !exists {
				g = graph.New(graph.StringHash, graph.Directed())
				treeGraphs[treeID] = g
			}

			_ = g.AddVertex(nodeID)
			for _, peer := range tree.EagerPeers {
				_ = g.AddVertex(peer)
				_ = g.AddEdge(nodeID, peer)
			}
		}
	}

	for treeID, g := range treeGraphs {
		gvFileName := "graphs/" + treeID + ".gv"
		file, err := os.Create(gvFileName)
		if err != nil {
			log.Printf("Failed to create file for %s: %v", treeID, err)
			continue
		}
		defer file.Close()

		err = draw.DOT(g, file)
		if err != nil {
			log.Printf("Failed to draw graph %s: %v", treeID, err)
		} else {
			// cmd := exec.Command("dot", "-Tsvg", "-O", gvFileName)
			// err := cmd.Run()
			// if err != nil {
			// 	log.Println("Error executing command:", err)
			// }
			// log.Printf("Graph %s written to %s.svg", treeID, treeID)
		}
	}

	// err = removeGVFiles("graphs")
	// if err != nil {
	// 	log.Fatalf("Failed to remove .gv files: %v", err)
	// }
}

func removeGVFiles(dir string) error {
	pattern := filepath.Join(dir, "*.gv")
	files, err := filepath.Glob(pattern)
	if err != nil {
		return err
	}

	for _, file := range files {
		err := os.Remove(file)
		if err != nil {
			log.Printf("Failed to delete file %s: %v", file, err)
		}
	}
	return nil
}
