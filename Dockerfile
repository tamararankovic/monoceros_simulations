########################
# -- 1. Build monoceros
########################
FROM golang:latest as monoceros_builder

WORKDIR /app

COPY ./monoceros/go.mod ./monoceros/go.sum ./

COPY ./hyparview ../hyparview
COPY ./plumtree ../plumtree

RUN go mod download

COPY ./monoceros/ .

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /monoceros ./cmd

########################
# -- 2. Build generator
########################
FROM golang:latest as generator_builder

WORKDIR /app

COPY ./monoceros_simulations/generator/go.mod ./monoceros_simulations/generator/go.sum ./

RUN go mod download

COPY ./monoceros_simulations/generator/ .

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /generator .

#############################################
# -- 3. Runtime image with Prometheus + apps
#############################################
FROM prom/prometheus:v2.53.3
# FROM alpine:latest

# Run as root
USER root

# Copy Go binaries
COPY --from=monoceros_builder  /monoceros  /usr/local/bin/monoceros/monoceros
COPY --from=generator_builder  /generator  /usr/local/bin/generator/generator


# Make them executable
RUN chmod 0777 /usr/local/bin/monoceros/monoceros \
    && chmod 0777 /usr/local/bin/generator/generator

# Allow nobody to access them (optional if you run as root)
RUN chown -R nobody:nobody /usr/local/bin/monoceros /usr/local/bin/generator

# Make log directory
RUN mkdir -p /var/log/monoceros

# Copy Prometheus configuration
COPY ./monoceros_simulations/prometheus /etc/prometheus

# Copy entrypoint script
COPY ./monoceros_simulations/entrypoint.sh /entrypoint.sh
RUN chmod 0777 /entrypoint.sh

# Expose relevant ports
EXPOSE 9090

ENTRYPOINT ["/entrypoint.sh"]