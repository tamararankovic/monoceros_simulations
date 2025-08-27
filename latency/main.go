package main

import (
	"log"
	"math"
	"os"
	"strconv"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("matrix dimension not specified")
	}
	if len(os.Args) < 3 {
		log.Fatal("intraregional latency not specified")
	}
	d, err := strconv.Atoi(os.Args[1])
	if err != nil {
		log.Fatal(err)
	}
	intraLatency, err := strconv.Atoi(os.Args[2])
	if err != nil {
		log.Fatal(err)
	}
	regions := 1
	interLatency := 0
	if len(os.Args) == 5 {
		regions, err = strconv.Atoi(os.Args[3])
		if err != nil {
			log.Fatal(err)
		}
		interLatency, err = strconv.Atoi(os.Args[4])
		if err != nil {
			log.Fatal(err)
		}
	}

	var matrix [][]int
	matrix = make([][]int, d)
	for i := range matrix {
		matrix[i] = make([]int, d)
	}

	for i := range d {
		for j := i + 1; j < d; j++ {
			if i == j {
				continue
			}
			latency := interLatency
			if getRegion(i, d, regions) == getRegion(j, d, regions) {
				latency = intraLatency
			}
			matrix[i][j] = latency
			matrix[j][i] = latency
		}
	}

	sb := strings.Builder{}
	for i := range d {
		for j := range d {
			sb.WriteString(strconv.Itoa(matrix[i][j]))
			if j < d-1 {
				sb.WriteString(" ")
			} else if i < d-1 {
				sb.WriteString("\n")
			}
		}
	}

	file, err := os.OpenFile("latency.txt", os.O_WRONLY|os.O_CREATE, 0666)
	if err != nil {
		log.Fatal(err)
	}
	_, err = file.WriteString(sb.String())
	if err != nil {
		log.Fatal(err)
	}
}

func getRegion(i, d, regions int) float64 {
	return math.Floor(float64(i) / (float64(d) / float64(regions)))
}
