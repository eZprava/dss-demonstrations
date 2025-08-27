#!/bin/bash
set -e

echo "=== DSS Build Script ==="

# Install OpenSSL for certificate generation
apt-get update && apt-get install -y openssl

# Create user and set permissions 
useradd -m dssuser -d /home/dssuser
mkdir -p /home/dssuser/.m2

echo "Generating self-signed SSL certificate..."

# Create output directory structure
mkdir -p /output/servercert

# OpenSSL configuration
cat > /tmp/ssl.conf << 'EOF'
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dssapi
req_extensions = v3_req

[dssapi]
C = CZ
ST = Czech Republic
L = Prague
O = Medax
OU = Backend Service
CN = DSS_API

[v3_req]
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1  = 127.0.0.1
EOF

# Add hostname and IP only if defined
if [ -n "${HOSTNAME}" ]; then
    echo "DNS.2 = ${HOSTNAME}" >> /tmp/ssl.conf
fi

if [ -n "${HOSTIP}" ]; then
    echo "IP.2  = ${HOSTIP}" >> /tmp/ssl.conf
fi

# Generate self-signed certificate
openssl req -new -x509 -nodes -days 365 \
    -keyout /output/servercert/server.key \
    -out /output/servercert/server.crt \
    -config /tmp/ssl.conf \
    -extensions v3_req

echo "Certificate generated successfully"

# Build Maven project 
echo "Building Maven project..."
cd /home/dssuser/dss-demonstrations

# Set ownership but run Maven as root 
chown -R dssuser:dssuser /home/dssuser/dss-demonstrations

# Run Maven build
echo "Running Maven build..."
mvn package -pl dss-standalone-app,dss-standalone-app-package,dss-demo-webapp -P quick

# Create output directory for applications
mkdir -p /output/webapps

# Copy built application using same pattern as working Dockerfile
echo "Copying built application..."

webapp_file=$(find /home/dssuser/dss-demonstrations/dss-demo-webapp/target -name "dss-demo-webapp-*.war" | head -1)

if [ -n "$webapp_file" ] && [ -f "$webapp_file" ]; then
    cp "$webapp_file" /output/webapps/ROOT.war
    echo "✅ Application copied successfully: $(basename "$webapp_file")"
else
    echo "❌ No WAR file found in expected location"
    echo "Searching for WAR files in target directory:"
    find /home/dssuser/dss-demonstrations/dss-demo-webapp/target -name "*.war" -ls 2>/dev/null || true
    
    echo "Contents of target directory:"
    ls -la /home/dssuser/dss-demonstrations/dss-demo-webapp/target/ 2>/dev/null || echo "Target directory not found"
    exit 1
fi

echo "Build script completed successfully"
echo "Output files:"
echo "  - SSL Certificate: /output/servercert/server.crt"
echo "  - SSL Key: /output/servercert/server.key"
echo "  - DSS Application: /output/webapps/ROOT.war"

# Verify outputs
echo ""
echo "=== Verification ==="
if [ -f "/output/servercert/server.crt" ]; then
    echo "✅ SSL Certificate: $(openssl x509 -in /output/servercert/server.crt -noout -subject)"
else
    echo "❌ SSL Certificate missing"
fi

if [ -f "/output/servercert/server.key" ]; then
    echo "✅ SSL Key: Present"
else
    echo "❌ SSL Key missing" 
fi

if [ -f "/output/webapps/ROOT.war" ]; then
    war_size=$(stat -c%s "/output/webapps/ROOT.war")
    echo "✅ DSS Application: $((war_size / 1024 / 1024))MB"
else
    echo "❌ DSS Application missing"
fi