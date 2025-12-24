# Auto-Secure Server - Security Foundation
FROM ubuntu:24.04

LABEL maintainer="Karac Von Thweatt"
LABEL description="Auto-Secure Server - Enterprise Security for Free"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Add universe repository for some packages
RUN echo "deb http://archive.ubuntu.com/ubuntu noble main universe" > /etc/apt/sources.list && \
    echo "deb http://archive.ubuntu.com/ubuntu noble-updates main universe" >> /etc/apt/sources.list && \
    echo "deb http://archive.ubuntu.com/ubuntu noble-security main universe" >> /etc/apt/sources.list

# Update and install core packages first
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg2 \
    lsb-release \
    software-properties-common \
    sudo \
    systemd \
    cron \
    logrotate \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

# Install Apache and PHP
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    apache2-utils \
    php \
    php-cli \
    php-common \
    php-mysql \
    php-gd \
    php-mbstring \
    php-curl \
    php-xml \
    php-bcmath \
    php-zip \
    php-opcache \
    libapache2-mod-php \
    && rm -rf /var/lib/apt/lists/*

# Install security tools - PART 1 (Install iptables-persistent first)
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iptables-persistent \
    && rm -rf /var/lib/apt/lists/*

# Install security tools - PART 2 (Install the rest, excluding the ones above)
RUN apt-get update && apt-get install -y --no-install-recommends \
    fail2ban \
    ufw \
    clamav \
    clamav-daemon \
    clamav-freshclam \
    rkhunter \
    aide \
    aide-common \
    lynis \
    apparmor \
    apparmor-utils \
    net-tools \
    iputils-ping \
    dnsutils \
    jq \
    git \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install additional security tools from different sources
RUN apt-get update && apt-get install -y --no-install-recommends \
    # logwatch is in universe
    logwatch \
    # sshguard might need a PPA or alternative
    # sshguard \
    # knockd might not be available
    # knockd \
    # auditd is usually installed by default
    auditd \
    && rm -rf /var/lib/apt/lists/*

# For tools not in Ubuntu 24.04 yet, install from source or use alternatives
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpcap-dev \
    && rm -rf /var/lib/apt/lists/*

# Install sshguard from source (if needed)
# RUN cd /tmp && \
#     wget https://github.com/sshguard/sshguard/releases/download/v2.4.2/sshguard-2.4.2.tar.gz && \
#     tar -xzf sshguard-2.4.2.tar.gz && \
#     cd sshguard-2.4.2 && \
#     ./configure && \
#     make && \
#     make install

# Create security user
RUN groupadd -r -g 1001 secuser && \
    useradd -r -u 1001 -g secuser -s /bin/bash -m -d /home/secuser secuser && \
    mkdir -p /etc/sudoers.d && \
    echo "secuser ALL=(ALL) NOPASSWD: /usr/sbin/service, /usr/sbin/fail2ban-client, /usr/sbin/ufw" > /etc/sudoers.d/secuser

# Enable Apache modules
RUN a2enmod rewrite headers ssl expires

# PHP security optimizations
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
    } > /etc/php/8.3/apache2/conf.d/99-security.ini

# Create necessary directories
RUN mkdir -p \
    /etc/fail2ban/jail.d \
    /var/lib/aide \
    /var/log/auto-secure \
    /var/lib/fail2ban \
    /var/log/clamav \
    && chown -R secuser:secuser /var/log/auto-secure

# Copy configuration files
COPY configs/ /tmp/configs/
RUN if [ -d "/tmp/configs" ]; then cp -r /tmp/configs/* /etc/ 2>/dev/null || true; fi && \
    rm -rf /tmp/configs

# Copy scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh 2>/dev/null || true

# Initialize security databases
RUN mkdir -p /var/lib/aide && \
    freshclam --quiet 2>/dev/null || true && \
    rkhunter --propupd 2>/dev/null || true

# Create default web page
RUN echo '<html><body><h1>Auto-Secure Server</h1><p>Enterprise security for $6/month</p></body></html>' > /var/www/html/index.html && \
    chown -R secuser:secuser /var/www/html

# Create health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/ 2>/dev/null || exit 1

# Switch to non-root user
USER secuser
WORKDIR /home/secuser

EXPOSE 80 443 22

# Use entrypoint if it exists, otherwise default command
CMD ["/bin/bash", "-c", "if [ -f /usr/local/bin/entrypoint.sh ]; then /usr/local/bin/entrypoint.sh; else apache2ctl -D FOREGROUND; fi"]