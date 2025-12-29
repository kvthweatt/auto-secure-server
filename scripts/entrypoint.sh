#!/bin/bash
set -e

echo "=== Auto-Secure Server ==="
echo "Starting security initialization..."

# Create necessary directories if they don't exist
mkdir -p /var/run/fail2ban /var/lib/fail2ban /var/log/clamav /run/sshd

# Start rsyslog if available
if command -v rsyslogd &> /dev/null; then
    echo "Starting rsyslog..."
    rsyslogd 2>/dev/null || true
fi

# Start cron if available
if command -v cron &> /dev/null; then
    echo "Starting cron..."
    cron 2>/dev/null || service cron start 2>/dev/null || true
fi

# Start apparmor if available
if command -v apparmor_parser &> /dev/null; then
    echo "Starting apparmor..."
    service apparmor start 2>/dev/null || true
fi

# Update ClamAV databases in background (non-blocking)
if command -v freshclam &> /dev/null; then
    echo "Updating ClamAV databases in background..."
    freshclam --quiet &
fi

# Apply kernel hardening if script exists
if [ -f /usr/local/bin/kernel-hardening.sh ]; then
    echo "Applying kernel hardening..."
    /usr/local/bin/kernel-hardening.sh 2>/dev/null || true
fi

# Initialize AIDE database if it doesn't exist
if command -v aideinit &> /dev/null && [ ! -f /var/lib/aide/aide.db ]; then
    echo "Initializing AIDE database..."
    aideinit --yes --force 2>/dev/null || true
fi

# Initialize fail2ban database
if [ ! -f /var/lib/fail2ban/fail2ban.sqlite3 ]; then
    echo "Initializing fail2ban database..."
    touch /var/lib/fail2ban/fail2ban.sqlite3
fi

# Update Cloudflare IPs in background
if [ -f /usr/local/bin/update-cloudflare-ips.sh ]; then
    echo "Updating Cloudflare IPs..."
    /usr/local/bin/update-cloudflare-ips.sh &
fi

# Start SSH
if command -v sshd &> /dev/null; then
    echo "Starting SSH server..."
    /usr/sbin/sshd -D &
fi

# Start Apache
if command -v apache2ctl &> /dev/null; then
    echo "Starting Apache..."
    apache2ctl -D FOREGROUND &
elif command -v httpd &> /dev/null; then
    echo "Starting Apache (httpd)..."
    httpd -D FOREGROUND &
fi

# Start Fail2Ban
if command -v fail2ban-server &> /dev/null; then
    echo "Starting Fail2Ban..."
    fail2ban-server -b 2>/dev/null || true
fi

# Start ClamAV daemon
if command -v clamd &> /dev/null; then
    echo "Starting ClamAV daemon..."
    clamd 2>/dev/null || true
fi

echo "=== Security initialization complete ==="
echo ""
echo "Available commands:"
echo "  - Run autoconfig: /usr/local/bin/autoconfig.sh"
echo "  - Check status: fail2ban-client status"
echo "  - Security audit: lynis audit system"
echo ""

# If a command was passed, execute it, otherwise keep container running
if [ $# -gt 0 ]; then
    echo "Executing: $@"
    exec "$@"
else
    echo "Container running. Use 'docker exec -it <container> bash' to access."
    # Keep container alive
    tail -f /dev/null
fi