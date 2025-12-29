FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install core security tools and dependencies
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl wget git sudo vim nano \
    # Init system for containers
    systemd systemd-sysv \
    # Security tools
    fail2ban ufw iptables-persistent \
    clamav clamav-daemon clamav-freshclam \
    aide lynis rkhunter chkrootkit \
    apparmor apparmor-utils \
    # Networking
    fwknop-server fwknop-client \
    openssh-server \
    # Web server
    apache2 \
    # Monitoring
    htop iotop iftop \
    # Logging
    rsyslog logrotate \
    # Other utilities
    unattended-upgrades \
    && rm -rf /var/lib/apt/lists/*

# Create directory structure
RUN mkdir -p /usr/local/bin \
    /var/log/security \
    /var/lib/security \
    /etc/auto-secure \
    /var/www/html

# Copy all scripts to /usr/local/bin (this is the key fix)
COPY scripts/*.sh /usr/local/bin/
RUN find /usr/local/bin -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; && \
    chmod +x /usr/local/bin/*.sh

# Copy configuration templates
COPY configs/ /etc/auto-secure/templates/

# Create secure user
RUN useradd -m -s /bin/bash -G sudo secuser && \
    echo "secuser:changeme" | chpasswd && \
    echo "secuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup SSH
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config

# Initialize ClamAV database
RUN freshclam || true

# Setup AIDE
RUN aideinit || true && \
    if [ -f /var/lib/aide/aide.db.new ]; then \
        mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db; \
    fi

# Expose ports
EXPOSE 22 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD /usr/local/bin/health-check.sh || exit 1

# Set the entrypoint script
COPY scripts/entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]