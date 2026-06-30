#!/bin/sh

# If no IP is passed during 'docker run', default to 127.0.0.1
TARGET_IP=${PROXY_IP:-127.0.0.1}

echo "Generating SSL Certificate for IP: $TARGET_IP"

mkdir -p /etc/nginx/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/certs/proxy.key \
    -out /etc/nginx/certs/proxy.crt \
    -subj "/CN=${TARGET_IP}" \
    -addext "subjectAltName=IP:${TARGET_IP}"

# Hand off control to Nginx
exec nginx -g "daemon off;"