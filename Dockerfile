# DSS API Docker Image - 2-stage build
# Simple, efficient and functional Docker image for DSS validation API

# ==========================================
# BUILD STAGE - Compile application and generate certificates
# ==========================================
FROM maven:3.9.11-eclipse-temurin-21 AS build

# Build environment variables
ENV HOSTNAME=
ENV HOSTIP=

# Copy build script and source code
COPY build.sh /build.sh
COPY . /home/dssuser/dss-demonstrations/

# Run build process
RUN chmod +x /build.sh && /build.sh

# ==========================================
# PRODUCTION STAGE - Runtime environment
# ==========================================
FROM tomcat:11.0.10-jdk21-temurin-noble

# Runtime environment variables
ENV LEDN=""
ENV HOSTNAME=
ENV HOSTIP=
ENV CATALINA_OPTS="-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"
ENV JAVA_OPTS="-Xms512m -Xmx2g -XX:MetaspaceSize=256m -XX:+UseG1GC -XX:+UseContainerSupport"

# Copy installation and runtime scripts
COPY install.sh /install.sh
COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh

# Copy built application and certificates from build stage
COPY --from=build /output/ /root/skeletondata/

# Run installation (packages, configurations, skeleton data)
RUN chmod +x /install.sh /entrypoint.sh /healthcheck.sh && \
    /install.sh && \
    rm /install.sh

# Create volume mount point for persistent data
VOLUME ["/vol"]

# Volume structure:
# /vol/servercert - SSL certificates (server.crt, server.key)
# /vol/logs - Application logs (ssh, tomcat, nginx, certbot, supervisor)
# /vol/sshaccess - SSH access keys for root user (id_rsa, id_rsa.pub, authorized_keys)

# Expose required ports
EXPOSE 8080 8443 80 22

# Health check configuration
HEALTHCHECK --interval=30s --timeout=15s --start-period=120s --retries=3 \
    CMD /healthcheck.sh

# Container entrypoint
ENTRYPOINT ["/entrypoint.sh"]