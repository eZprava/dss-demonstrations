#!/bin/bash

# DSS Container Health Check Script
# Returns 0 if healthy, 1 if unhealthy

HEALTHY=0
UNHEALTHY=1

# Check if supervisor is running
if ! pgrep -f "supervisord" > /dev/null; then
    echo "UNHEALTHY: Supervisor not running"
    exit $UNHEALTHY
fi

# Check SSH service
if ! pgrep -f "sshd" > /dev/null; then
    echo "UNHEALTHY: SSH service not running"
    exit $UNHEALTHY
fi

# Check Tomcat service
if ! pgrep -f "java.*catalina" > /dev/null; then
    echo "UNHEALTHY: Tomcat service not running"
    exit $UNHEALTHY
fi

# Check if Tomcat is responding
if ! curl -s -f http://localhost:8080/ > /dev/null 2>&1; then
    echo "UNHEALTHY: Tomcat not responding on port 8080"
    exit $UNHEALTHY
fi

# Check Nginx service
if ! pgrep -f "nginx" > /dev/null; then
    echo "UNHEALTHY: Nginx service not running"
    exit $UNHEALTHY
fi

# Check if Nginx HTTPS is responding
if ! curl -s -k -f https://localhost:8443/ > /dev/null 2>&1; then
    echo "UNHEALTHY: Nginx HTTPS not responding on port 8443"
    exit $UNHEALTHY
fi

# Check if SSL certificates exist and are valid
if [ ! -f "/vol/servercert/server.crt" ] || [ ! -f "/vol/servercert/server.key" ]; then
    echo "UNHEALTHY: SSL certificates missing"
    exit $UNHEALTHY
fi

# Verify SSL certificate is not expired
if ! openssl x509 -in /vol/servercert/server.crt -checkend 86400 > /dev/null 2>&1; then
    echo "UNHEALTHY: SSL certificate expired or expires within 24 hours"
    exit $UNHEALTHY
fi

# Check if DSS application is deployed
if [ ! -f "/usr/local/tomcat/webapps/ROOT.war" ]; then
    echo "UNHEALTHY: DSS application WAR file missing"
    exit $UNHEALTHY
fi

# All checks passed
echo "HEALTHY: All services running normally"
exit $HEALTHY