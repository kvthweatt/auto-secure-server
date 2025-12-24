# Auto-Secure Server - Security Foundation for Any Application
# Builds a complete security-hardened base container

# Stage 1: Builder for optimized layers
FROM ubuntu:24.04 as builder

# Non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Create minimal security user first
RUN groupadd -r -g 1001 secuser && \
    useradd -r -u 1001 -g secuser -s /bin/bash -m -d /home/secuser secuser && \
    mkdir -p /etc/sudoers.d && \
    echo "secuser ALL=(ALL) NOPASSWD: /usr/sbin/service, /usr/sbin/fail2ban-client, /usr/sbin/ufw" > /etc/sudoers.d/secuser

# Stage 2: Final image
FROM ubuntu:24.04

LABEL maintainer="Your Name <your@email.com>"
LABEL description="Auto-Secure Server - Enterprise-grade security for $6/month"
LABEL version="1.0.0"
LABEL security.scan="lynis-score:85+"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Copy security user from builder
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
COPY --from=builder /etc/sudoers.d/secuser /etc/sudoers.d/secuser

# Install everything in one RUN layer (optimized for cache)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core
    ca-certificates curl wget gnupg2 lsb-release software-properties-common \
    sudo systemctl systemd systemd-sysv cron logrotate rsyslog \
    # Web stack
    apache2 apache2-utils \
    php8.3 php8.3-cli php8.3-common php8.3-mysql php8.3-gd php8.3-mbstring \
    php8.3-curl php8.3-xml php8.3-bcmath php8.3-zip php8.3-opcache \
    libapache2-mod-php8.3 \
    # Security stack
    fail2ban sshguard ufw \
    clamav clamav-daemon clamav-freshclam \
    rkhunter chkrootkit aide aide-common \
    lynis tripwire logwatch \
    apparmor apparmor-utils apparmor-profiles \
    iptables iptables-persistent ipset iproute2 \
    knockd auditd audit-viewer \
    # Utilities
    net-tools iputils-ping dnsutils nmap whois \
    jq git unzip zip tar gzip bzip2 \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Enable Apache modules
RUN a2enmod rewrite headers ssl expires proxy proxy_http proxy_balancer cache

# PHP optimizations for security
RUN { \
    echo 'memory_limit = 128M'; \
    echo 'upload_max_filesize = 64M'; \
    echo 'post_max_size = 64M'; \
    echo 'max_execution_time = 300'; \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'expose_php = Off'; \
    echo 'display_errors = Off'; \
    echo 'log_errors = On'; \
    } > /etc/php/8.3/apache2/conf.d/99-security.ini

# Copy configuration files
COPY configs/ /tmp/configs/
RUN cp -r /tmp/configs/* /etc/ && rm -rf /tmp/configs

# Copy scripts and make executable
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Initialize security databases
RUN mkdir -p /var/lib/aide && \
    aideinit --yes --force && \
    freshclam --quiet && \
    tripwire --init -c /etc/tripwire/tw.cfg -p /etc/tripwire/tw.pol --silent && \
    rkhunter --propupd && \
    mkdir -p /var/log/auto-secure && \
    chown -R secuser:secuser /var/log/auto-secure

# Create health check script
RUN echo '#!/bin/bash\ncurl -f http://localhost/ 2>/dev/null || exit 1' > /healthcheck.sh && \
    chmod +x /healthcheck.sh

# Create directories with proper permissions
RUN mkdir -p /var/www/html /var/log/apache2 /var/log/fail2ban /var/lib/fail2ban && \
    chown -R secuser:secuser /var/www/html && \
    chmod 755 /var/www/html

# Setup cron jobs for security updates
COPY configs/cron/security-jobs /etc/cron.d/auto-secure
RUN chmod 0644 /etc/cron.d/auto-secure && \
    crontab /etc/cron.d/auto-secure

# Switch to non-root user
USER secuser
WORKDIR /home/secuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD /healthcheck.sh

# Expose ports
EXPOSE 80 443 22

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]