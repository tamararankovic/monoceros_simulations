// File: main.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"strings"

	dto "github.com/prometheus/client_model/go"
	"github.com/prometheus/common/expfmt"
)

// Static OpenMetrics payload (10 metrics, ~80 % gauges)
const metrics = `# HELP app_request_processing_time_seconds Average request processing time
# TYPE app_request_processing_time_seconds gauge
app_request_processing_time_seconds 0.256

# HELP app_memory_usage_bytes Current memory usage in bytes
# TYPE app_memory_usage_bytes gauge
app_memory_usage_bytes 512000000

# HELP app_cpu_load_ratio CPU load (0-1)
# TYPE app_cpu_load_ratio gauge
app_cpu_load_ratio 0.13

# HELP app_active_sessions Current active user sessions
# TYPE app_active_sessions gauge
app_active_sessions 42

# HELP app_queue_depth_pending_jobs Jobs waiting in queue
# TYPE app_queue_depth_pending_jobs gauge
app_queue_depth_pending_jobs 7

# HELP app_cache_hit_ratio Cache hit ratio
# TYPE app_cache_hit_ratio gauge
app_cache_hit_ratio 0.82

# HELP app_current_goroutines Goroutine count
# TYPE app_current_goroutines gauge
app_current_goroutines 33

# HELP app_last_backup_timestamp_seconds Unix timestamp of last successful backup
# TYPE app_last_backup_timestamp_seconds gauge
app_last_backup_timestamp_seconds 1.700000e+09

# HELP app_http_requests_total Total HTTP requests processed
# TYPE app_http_requests_total counter
app_http_requests_total 12890

# HELP app_errors_total Total errors encountered
# TYPE app_errors_total counter
app_errors_total 17

# EOF
`

func metricsHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/openmetrics-text; version=1.0.0; charset=utf-8")
	fmt.Fprint(w, metrics)
}

func main() {
	// parsed, err := parseMetrics(metrics)
	// if err != nil {
	// 	log.Fatal(err)
	// }
	// for k, v := range parsed {
	// 	log.Println(k)
	// 	log.Println(v)
	// 	log.Println()
	// }

	http.HandleFunc("/metrics", metricsHandler)
	log.Println("Metrics generator listening on :9100/metrics")

	log.Fatal(http.ListenAndServe(":9100", nil))
}

func parseMetrics(data string) (map[string]*dto.MetricFamily, error) {
	parser := expfmt.TextParser{}
	mf, err := parser.TextToMetricFamilies(strings.NewReader(data))
	if err != nil {
		return nil, err
	}
	return mf, nil
}
