#!/bin/bash
set -e

echo "=== DSS Installation Script ==="

# Update package list and install required packages
echo "Installing required packages..."
apt-get update && apt-get install --no-install-recommends -qy \
    openssh-server \
    nginx \
    certbot \
    python3-certbot-nginx \
    supervisor \
    curl \
    mc \
    net-tools \
    nano \
    && rm -rf /var/lib/apt/lists/*


# Configure SSH
echo "Configuring SSH..."
mkdir -p /var/run/sshd
mkdir -p /root/skeletondata/sshaccess

# Generate SSH host keys if they don't exist
ssh-keygen -A

# Create SSH key pair for root access
if [ ! -f /root/skeletondata/sshaccess/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f /root/skeletondata/sshaccess/id_rsa -N "" -C "root@dss-api"
fi

# Configure SSH for root access
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile /root/.ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# Set up authorized keys
mkdir -p /root/skeletondata/sshaccess
if [ -f /root/skeletondata/sshaccess/id_rsa.pub ]; then
    cp /root/skeletondata/sshaccess/id_rsa.pub /root/skeletondata/sshaccess/authorized_keys
fi

# Create skeleton logs directory
mkdir -p /root/skeletondata/logs/{ssh,tomcat,nginx,certbot,supervisor}

# Copy DSS application from build stage directly to Tomcat
echo "Deploying DSS application..."
if [ -d "/root/skeletondata/webapps" ] && [ -f "/root/skeletondata/webapps/ROOT.war" ]; then
    cp "/root/skeletondata/webapps/ROOT.war" "/usr/local/tomcat/webapps/ROOT.war"
    echo "✅ DSS application deployed to Tomcat"
    # Remove webapps from skeleton data as it's no longer needed
    rm -rf /root/skeletondata/webapps
else
    echo "⚠️  DSS application not found in build output - will be deployed during runtime"
fi

# Configure Tomcat - add CORS filter (ZŮSTÁVÁ!!!)
echo "Configuring Tomcat..."
if [ -f /usr/local/tomcat/conf/web.xml ]; then
    # Backup original web.xml
    cp /usr/local/tomcat/conf/web.xml /usr/local/tomcat/conf/web.xml.orig
    
    # Add CORS filter before </web-app>
    sed -i '/<\/web-app>/i\
    <!-- CORS Filter -->\
    <filter>\
        <filter-name>CorsFilter</filter-name>\
        <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>\
        <init-param>\
            <param-name>cors.allowed.origins</param-name>\
            <param-value>*</param-value>\
        </init-param>\
        <init-param>\
            <param-name>cors.allowed.methods</param-name>\
            <param-value>GET,POST,PUT,DELETE,OPTIONS,HEAD</param-value>\
        </init-param>\
        <init-param>\
            <param-name>cors.allowed.headers</param-name>\
            <param-value>Content-Type,X-Requested-With,Accept,Authorization,Cache-Control</param-value>\
        </init-param>\
        <init-param>\
            <param-name>cors.exposed.headers</param-name>\
            <param-value>Access-Control-Allow-Origin,Access-Control-Allow-Credentials</param-value>\
        </init-param>\
        <init-param>\
            <param-name>cors.support.credentials</param-name>\
            <param-value>false</param-value>\
        </init-param>\
        <init-param>\
            <param-name>cors.preflight.maxage</param-name>\
            <param-value>10</param-value>\
        </init-param>\
    </filter>\
    <filter-mapping>\
        <filter-name>CorsFilter</filter-name>\
        <url-pattern>/*</url-pattern>\
    </filter-mapping>' /usr/local/tomcat/conf/web.xml
fi

# Configure Supervisor
echo "Configuring Supervisor..."
mkdir -p /etc/supervisor/conf.d

cat > /etc/supervisor/supervisord.conf << 'EOF'
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
logfile=/vol/logs/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
childlogdir=/vol/logs/supervisor
nodaemon=true
silent=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[include]
files = /etc/supervisor/conf.d/*.conf
EOF

# SSH service configuration
cat > /etc/supervisor/conf.d/ssh.conf << 'EOF'
[program:ssh]
command=/usr/sbin/sshd -D
autostart=true
autorestart=true
priority=10
stdout_logfile=/vol/logs/ssh/ssh.log
stderr_logfile=/vol/logs/ssh/ssh_error.log
EOF

# Tomcat service configuration
cat > /etc/supervisor/conf.d/tomcat.conf << 'EOF'
[program:tomcat]
command=/usr/local/tomcat/bin/catalina.sh run
autostart=true
autorestart=true
priority=20
stdout_logfile=/vol/logs/tomcat/catalina.out
stderr_logfile=/vol/logs/tomcat/catalina_error.log
environment=CATALINA_OPTS="%(ENV_CATALINA_OPTS)s",JAVA_OPTS="%(ENV_JAVA_OPTS)s"
EOF

# Nginx service configuration
cat > /etc/supervisor/conf.d/nginx.conf << 'EOF'
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
priority=30
stdout_logfile=/vol/logs/nginx/access.log
stderr_logfile=/vol/logs/nginx/error.log
EOF

# Status report service configuration - ZMĚNA: přesměrování výstupu do konzole
cat > /etc/supervisor/conf.d/status_report.conf << 'EOF'
[program:status_report]
command=/bin/status_report_service
autostart=true
autorestart=false
priority=40
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

# Create status_report script in /bin
echo "Creating status_report script..."
cat > /bin/status_report << 'EOF'
#!/bin/bash

echo "========================================"
echo "DSS API Container Status Report"
echo "========================================"
echo "Timestamp: $(date)"
echo ""

# Container information
echo "=== Container Information ==="
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Java: $(java -version 2>&1 | head -1)"
echo "Tomcat: $(cat /usr/local/tomcat/RELEASE-NOTES | grep "Apache Tomcat" | head -1 | cut -d' ' -f3-4)"
echo "Nginx: $(nginx -v 2>&1)"
echo ""

# Service status
echo "=== Service Status ==="
if pgrep -f "sshd" > /dev/null; then
    echo "✅ SSH: Running (Port 22)"
else
    echo "❌ SSH: Not running"
fi

if pgrep -f "java.*catalina" > /dev/null; then
    echo "✅ Tomcat: Running (Port 8080)"
    
    # Check for WAR applications
    if [ -f "/usr/local/tomcat/webapps/ROOT.war" ]; then
        echo "   └── DSS Validation API: Deployed"
    fi
else
    echo "❌ Tomcat: Not running"
fi

if pgrep -f "nginx" > /dev/null; then
    echo "✅ Nginx: Running (Port 8443/443)"
else
    echo "❌ Nginx: Not running"
fi

echo ""

# Network information with proper host resolution
echo "=== Network Information ==="

# Determine the host to use for external access
# Priority: ENV HOSTIP > ENV HOSTNAME > localhost
if [ -n "$HOSTIP" ] && [ "$HOSTIP" != "" ]; then
    ACCESS_HOST="$HOSTIP"
    echo "Host IP (ENV): $HOSTIP"
elif [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "" ]; then
    ACCESS_HOST="$HOSTNAME"
    echo "Hostname (ENV): $HOSTNAME"
else
    ACCESS_HOST="localhost"
    echo "Hostname: localhost (default)"
fi

# Also show container internal IP for reference
CONTAINER_IP=$(hostname -I | awk '{print $1}')
echo "Container Internal IP: $CONTAINER_IP (Docker network)"

echo ""

# Endpoint availability
echo "=== Endpoint Availability ==="

# Check HTTP endpoint
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ | grep -q "200\|302\|404"; then
    echo "✅ HTTP Tomcat: http://$ACCESS_HOST:8080/"
    if [ -n "$HOSTNAME" ] && [ "$ACCESS_HOST" != "$HOSTNAME" ] && [ "$HOSTNAME" != "" ]; then
        echo "   └── http://$HOSTNAME:8080/ (alternative)"
    fi
else
    echo "❌ HTTP Tomcat: Not available"
fi

# Check HTTPS endpoint
if curl -s -k -o /dev/null -w "%{http_code}" https://localhost:8443/ | grep -q "200\|302\|404"; then
    echo "✅ HTTPS Nginx: https://$ACCESS_HOST:8443/"
    if [ -n "$HOSTNAME" ] && [ "$ACCESS_HOST" != "$HOSTNAME" ] && [ "$HOSTNAME" != "" ]; then
        echo "   └── https://$HOSTNAME:8443/ (alternative)"
    fi
else
    echo "❌ HTTPS Nginx: Not available"
fi

echo ""

# SSL Certificate information
echo "=== SSL Certificate Information ==="
if [ -f "/vol/servercert/server.crt" ]; then
    echo "Certificate Subject: $(openssl x509 -in /vol/servercert/server.crt -noout -subject | cut -d'=' -f2-)"
    echo "Certificate Validity: $(openssl x509 -in /vol/servercert/server.crt -noout -dates | grep notAfter | cut -d'=' -f2)"
else
    echo "❌ SSL Certificate not found"
fi

echo ""

# SSH Access information
echo "=== SSH Access Information ==="
echo "SSH Access: ssh root@$ACCESS_HOST"
if [ -n "$HOSTNAME" ] && [ "$ACCESS_HOST" != "$HOSTNAME" ] && [ "$HOSTNAME" != "" ]; then
    echo "            ssh root@$HOSTNAME (alternative)"
fi

if [ -f "/vol/sshaccess/id_rsa" ]; then
    echo "Private key available at: /vol/sshaccess/id_rsa"
    echo "Public key fingerprint:"
    ssh-keygen -lf /vol/sshaccess/id_rsa.pub 2>/dev/null || echo "Unable to read key fingerprint"
fi

echo ""
echo "========================================"
EOF

chmod +x /bin/status_report

# Create status report service wrapper - UPRAVENO: přidáno více debug informací
cat > /bin/status_report_service << 'EOF'
#!/bin/bash

echo "=== Status Report Service Starting ==="
echo "Waiting for services to be ready..."

# Wait for Tomcat with timeout and progress indication
echo "Checking Tomcat availability..."
TOMCAT_RETRIES=0
MAX_RETRIES=60  # 2 minutes timeout
while ! curl -s http://localhost:8080/ > /dev/null 2>&1; do
    if [ $TOMCAT_RETRIES -ge $MAX_RETRIES ]; then
        echo "❌ Timeout waiting for Tomcat to start"
        exit 1
    fi
    echo "Waiting for Tomcat... (attempt $((TOMCAT_RETRIES + 1))/$MAX_RETRIES)"
    sleep 2
    TOMCAT_RETRIES=$((TOMCAT_RETRIES + 1))
done
echo "✅ Tomcat is ready"

# Wait for Nginx with timeout and progress indication
echo "Checking Nginx availability..."
NGINX_RETRIES=0
while ! curl -s -k https://localhost:8443/ > /dev/null 2>&1; do
    if [ $NGINX_RETRIES -ge $MAX_RETRIES ]; then
        echo "❌ Timeout waiting for Nginx to start"
        exit 1
    fi
    echo "Waiting for Nginx HTTPS... (attempt $((NGINX_RETRIES + 1))/$MAX_RETRIES)"
    sleep 2
    NGINX_RETRIES=$((NGINX_RETRIES + 1))
done
echo "✅ Nginx is ready"

echo ""
echo "🎉 All services are ready! Generating status report..."
echo ""

# Run the status report
/bin/status_report

echo ""
echo "=== Status Report Service Completed ==="
echo "This service will now keep running in the background."

# Keep the service running but don't restart
sleep infinity
EOF

chmod +x /bin/status_report_service

# Create basic Nginx configuration - NO CORS
echo "Creating Nginx configuration..."
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
EOF_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;        

        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;
        proxy_hide_header Access-Control-Expose-Headers;
        proxy_hide_header Access-Control-Allow-Credentials;
        proxy_hide_header Access-Control-Max-Age;       
    }
}

# HTTP redirect to HTTPS
server {
    listen 80;
    server_name _;
    return 301 https://$host:8443$request_uri;
}
EOF

echo "Installation completed successfully!"
echo "Skeleton data structure created in /root/skeletondata/"

# Restart nginx to apply configuration changes
echo "Restarting nginx to apply CORS configuration..."
nginx -t && nginx -s reload 2>/dev/null || echo "Nginx will be started by supervisor"