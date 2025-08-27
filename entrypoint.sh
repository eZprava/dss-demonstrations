#!/bin/bash
set -e

echo "=== DSS Container Entrypoint ==="

# Ensure /vol directory exists
if [ ! -d "/vol" ]; then
    echo "Creating /vol directory..."
    mkdir -p /vol
fi

# Initialize volume structure from skeleton data if needed
echo "Checking volume structure..."

# Check and copy servercert
if [ ! -d "/vol/servercert" ] || [ -z "$(ls -A /vol/servercert 2>/dev/null)" ]; then
    echo "Initializing SSL certificates..."
    mkdir -p /vol/servercert
    if [ -d "/root/skeletondata/servercert" ]; then
        cp -r /root/skeletondata/servercert/* /vol/servercert/
    fi
fi

# Check and copy sshaccess
if [ ! -d "/vol/sshaccess" ] || [ -z "$(ls -A /vol/sshaccess 2>/dev/null)" ]; then
    echo "Initializing SSH access keys..."
    mkdir -p /vol/sshaccess
    if [ -d "/root/skeletondata/sshaccess" ]; then
        cp -r /root/skeletondata/sshaccess/* /vol/sshaccess/
    fi
fi

# Check and copy logs structure
if [ ! -d "/vol/logs" ]; then
    echo "Initializing logs directory..."
    mkdir -p /vol/logs
    if [ -d "/root/skeletondata/logs" ]; then
        cp -r /root/skeletondata/logs/* /vol/logs/
    else
        # Create log directories if skeleton doesn't exist
        mkdir -p /vol/logs/{ssh,tomcat,nginx,certbot,supervisor}
    fi
fi

# Create symlinks for SSH access
echo "Setting up SSH access..."
mkdir -p /root/.ssh

# Remove existing files/links if they exist
rm -f /root/.ssh/authorized_keys
rm -f /root/.ssh/id_rsa
rm -f /root/.ssh/id_rsa.pub

# Create symlinks to persistent storage
if [ -f "/vol/sshaccess/authorized_keys" ]; then
    ln -sf /vol/sshaccess/authorized_keys /root/.ssh/authorized_keys
fi
if [ -f "/vol/sshaccess/id_rsa" ]; then
    ln -sf /vol/sshaccess/id_rsa /root/.ssh/id_rsa
fi
if [ -f "/vol/sshaccess/id_rsa.pub" ]; then
    ln -sf /vol/sshaccess/id_rsa.pub /root/.ssh/id_rsa.pub
fi

# Set proper permissions for SSH
chmod 700 /root/.ssh
if [ -f "/vol/sshaccess/id_rsa" ]; then
    chmod 600 /vol/sshaccess/id_rsa
fi
if [ -f "/vol/sshaccess/authorized_keys" ]; then
    chmod 600 /vol/sshaccess/authorized_keys
fi

# Handle Let's Encrypt or self-signed certificates
echo "Setting up SSL certificates..."

if [ -n "$LEDN" ] && [ "$LEDN" != "" ]; then
    echo "Let's Encrypt domain configured: $LEDN"
    
    # Update Nginx configuration for Let's Encrypt - ČISTÝ PROXY
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name $LEDN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$server_name:8443\$request_uri;
    }
}

server {
    listen 8443 ssl;
    server_name $LEDN;

    ssl_certificate /etc/letsencrypt/live/$LEDN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$LEDN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        # ČISTÝ PROXY - žádné CORS headers (Tomcat je řeší)
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Create Certbot configuration
    cat > /etc/supervisor/conf.d/certbot.conf << 'EOF'
[program:certbot]
command=/bin/bash -c 'if [ ! -d "/etc/letsencrypt/live/$LEDN" ]; then certbot certonly --webroot -w /var/www/html -d $LEDN --non-interactive --agree-tos --email admin@$LEDN; fi && while true; do certbot renew --quiet; sleep 12h; done'
autostart=true
autorestart=true
priority=35
stdout_logfile=/vol/logs/certbot/certbot.log
stderr_logfile=/vol/logs/certbot/certbot_error.log
environment=LEDN="%(ENV_LEDN)s"
EOF

    mkdir -p /var/www/html

else
    echo "Using self-signed certificates..."
    
    # Update Nginx configuration for self-signed certificates - ČISTÝ PROXY
    cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 8443 ssl;
    server_name _;

    ssl_certificate /vol/servercert/server.crt;
    ssl_certificate_key /vol/servercert/server.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        # ČISTÝ PROXY - žádné CORS headers (Tomcat je řeší)
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name _;
    return 301 https://$host:8443$request_uri;
}
EOF
fi

# Verify SSL certificates exist
if [ ! -f "/vol/servercert/server.crt" ] || [ ! -f "/vol/servercert/server.key" ]; then
    echo "❌ SSL certificates not found! Container may not work properly."
    echo "Expected files:"
    echo "  - /vol/servercert/server.crt"
    echo "  - /vol/servercert/server.key"
    exit 1
fi

# Verify application WAR file exists
if [ ! -f "/usr/local/tomcat/webapps/ROOT.war" ]; then
    echo "❌ DSS application WAR file not found!"
    echo "Expected: /usr/local/tomcat/webapps/ROOT.war"
    echo "This should have been deployed during installation phase."
    ls -la /usr/local/tomcat/webapps/ 2>/dev/null || echo "Webapps directory not accessible"
    exit 1
fi

echo "✅ DSS application ready: $(ls -lh /usr/local/tomcat/webapps/ROOT.war | awk '{print $5}')"

echo "✅ Container initialization completed"
echo "✅ Volume structure verified"
echo "✅ SSL certificates ready"
echo "✅ SSH access configured"
echo "✅ DSS application ready"

echo ""
echo "Starting services via Supervisor..."
echo "========================================"

# Start supervisor which will manage all services
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf