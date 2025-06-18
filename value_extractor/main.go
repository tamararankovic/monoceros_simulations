package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
)

type StateResponse struct {
	ID            string `json:"Id"`
	LatestMetrics struct {
		RRN string `json:"RRN"`
	} `json:"LatestMetrics"`
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

	for port := startPort; port <= endPort; port++ {
		url := fmt.Sprintf("http://localhost:%d/state", port)
		resp, err := http.Get(url)
		if err != nil {
			log.Printf("Failed to request %s: %v", url, err)
			continue
		}
		body, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			log.Printf("Failed to read response from %s: %v", url, err)
			continue
		}

		var state StateResponse
		if err := json.Unmarshal(body, &state); err != nil {
			log.Printf("Failed to unmarshal response from %s: %v", url, err)
			continue
		}

		value := extractGlobalMemoryTotal(state.LatestMetrics.RRN)
		if value != "" {
			fmt.Printf("%s - %s\n", state.ID, value)
		}
	}
}

func extractGlobalMemoryTotal(metrics string) string {
	re := regexp.MustCompile(`total_app_memory_usage_bytes\{[^}]*global="y"[^}]*\}\s+([0-9.eE+-]+)`)
	match := re.FindStringSubmatch(metrics)
	if len(match) == 2 {
		return match[1]
	}
	return ""
}
