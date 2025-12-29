#!/bin/bash
# Auto-Secure Server - Automated Configuration Orchestrator
# This script walks through all security tools in the proper order

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration file
CONFIG_FILE="/etc/auto-secure/config.env"
STATE_FILE="/var/lib/security/autoconfig.state"

# Logging
LOG_FILE="/var/log/security/autoconfig.log"
mkdir -p /var/log/security /var/lib/security

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
    log "STEP: $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC}) [${default}]: " input
        eval "$var_name=\"${input:-$default}\""
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}): " input
        eval "$var_name=\"$input\""
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    
    if [ "$default" = "y" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC}) [Y/n]: " response
        response=${response:-y}
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}) [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

save_config() {
    local key="$1"
    local value="$2"
    echo "export $key=\"$value\"" >> "$CONFIG_FILE"
}

mark_step_complete() {
    echo "$1" >> "$STATE_FILE"
}

is_step_complete() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

# Initialize configuration
initialize_config() {
    print_header "Auto-Secure Server Configuration"
    
    echo "This wizard will guide you through configuring all security tools."
    echo "You can run this again later to reconfigure individual components."
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        if prompt_yes_no "Existing configuration found. Start fresh?" "n"; then
            rm -f "$CONFIG_FILE" "$STATE_FILE"
        else
            source "$CONFIG_FILE"
            echo "Loading existing configuration..."
            return 0
        fi
    fi
    
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    print_step "Gathering basic information..."
    
    prompt_input "Server hostname" HOSTNAME "$(hostname)"
    prompt_input "Admin email address" ADMIN_EMAIL "admin@localhost"
    prompt_input "Timezone" TZ "UTC"
    
    save_config "HOSTNAME" "$HOSTNAME"
    save_config "ADMIN_EMAIL" "$ADMIN_EMAIL"
    save_config "TZ" "$TZ"
    
    print_success "Basic configuration saved"
}

# 1. System Hardening (First - no dependencies)
configure_kernel_hardening() {
    if is_step_complete "kernel_hardening"; then
        print_warning "Kernel hardening already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 1: Kernel Hardening"
    
    echo "Applying kernel security parameters..."
    
    cat > /etc/sysctl.d/99-auto-secure.conf <<EOF
# IP Forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Syn flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096

# Disable ICMP redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Protect against tcp time-wait assassination
net.ipv4.tcp_rfc1337 = 1

# Additional hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

    sysctl -p /etc/sysctl.d/99-auto-secure.conf
    
    print_success "Kernel hardening applied"
    mark_step_complete "kernel_hardening"
}

# 2. SSH Configuration (Before fwknop and fail2ban depend on it)
configure_ssh() {
    if is_step_complete "ssh"; then
        print_warning "SSH already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 2: SSH Hardening"
    
    prompt_input "SSH port" SSH_PORT "22"
    save_config "SSH_PORT" "$SSH_PORT"
    
    echo "Configuring SSH..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    cat > /etc/ssh/sshd_config <<EOF
Port $SSH_PORT
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Rate limiting
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30

# Allow only specific users
AllowUsers secuser
EOF

    print_success "SSH configured on port $SSH_PORT"
    
    if prompt_yes_no "Generate SSH key pair for secuser?" "y"; then
        su - secuser -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
        su - secuser -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''"
        print_success "SSH key generated at /home/secuser/.ssh/id_ed25519"
        echo -e "${YELLOW}Public key:${NC}"
        cat /home/secuser/.ssh/id_ed25519.pub
    fi
    
    # Don't restart SSH yet - wait until fwknop is configured
    print_warning "SSH will be restarted after fwknop configuration"
    
    mark_step_complete "ssh"
}

# 3. fwknop (Port knocking - must be before firewall rules lock everything)
configure_fwknop() {
    if is_step_complete "fwknop"; then
        print_warning "fwknop already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 3: fwknop (Port Knocking)"
    
    echo "fwknop provides Single Packet Authorization (SPA) for SSH."
    echo "This hides your SSH port until you 'knock' with the right key."
    echo ""
    
    if prompt_yes_no "Enable fwknop port knocking?" "y"; then
        
        # Generate random key and HMAC key
        FWKNOP_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
        FWKNOP_HMAC=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
        
        save_config "FWKNOP_KEY" "$FWKNOP_KEY"
        save_config "FWKNOP_HMAC" "$FWKNOP_HMAC"
        
        # Configure fwknop server
        cat > /etc/fwknop/access.conf <<EOF
SOURCE: ANY
OPEN_PORTS: tcp/$SSH_PORT
KEY: $FWKNOP_KEY
HMAC_KEY: $FWKNOP_HMAC
FW_ACCESS_TIMEOUT: 30
REQUIRE_SOURCE_ADDRESS: Y
EOF

        cat > /etc/fwknop/fwknopd.conf <<EOF
PCAP_INTF: eth0
ENABLE_IPT_FORWARDING: N
ENABLE_IPT_LOCAL_NAT: N
ENABLE_IPT_SNAT: N
ENABLE_IPT_OUTPUT: N
FLUSH_IPT_AT_INIT: Y
FLUSH_IPT_AT_EXIT: Y
EOF

        # Create client configuration
        mkdir -p /home/secuser/.fwknop
        cat > /home/secuser/.fwknop/config <<EOF
[default]
ACCESS: tcp/$SSH_PORT
KEY: $FWKNOP_KEY
HMAC_KEY: $FWKNOP_HMAC
EOF
        chown -R secuser:secuser /home/secuser/.fwknop
        chmod 600 /home/secuser/.fwknop/config
        
        print_success "fwknop configured"
        echo ""
        echo -e "${GREEN}Client connection command:${NC}"
        echo "  fwknop -n $HOSTNAME && ssh -p $SSH_PORT secuser@$HOSTNAME"
        echo ""
        echo -e "${YELLOW}Save these credentials securely:${NC}"
        echo "  KEY: $FWKNOP_KEY"
        echo "  HMAC: $FWKNOP_HMAC"
        echo ""
        
        systemctl enable fwknopd
        systemctl start fwknopd
        
        save_config "FWKNOP_ENABLED" "true"
    else
        save_config "FWKNOP_ENABLED" "false"
    fi
    
    mark_step_complete "fwknop"
}

# 4. Firewall (After fwknop, before fail2ban)
configure_firewall() {
    if is_step_complete "firewall"; then
        print_warning "Firewall already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 4: Firewall (UFW)"
    
    echo "Configuring firewall rules..."
    
    # Reset UFW
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow essential services
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # SSH access
    if [ "${FWKNOP_ENABLED}" = "true" ]; then
        print_warning "SSH port $SSH_PORT will be protected by fwknop (no static rule)"
    else
        if prompt_yes_no "Allow SSH port $SSH_PORT through firewall?" "y"; then
            ufw allow $SSH_PORT/tcp comment 'SSH'
        fi
    fi
    
    # Enable UFW
    ufw --force enable
    
    print_success "Firewall configured and enabled"
    ufw status verbose
    
    mark_step_complete "firewall"
}

# 5. Fail2Ban (After firewall rules are set)
configure_fail2ban() {
    if is_step_complete "fail2ban"; then
        print_warning "Fail2Ban already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 5: Fail2Ban (Intrusion Prevention)"
    
    echo "Configuring Fail2Ban with Cloudflare & Google whitelisting..."
    
    # Fetch whitelisted IPs
    echo "Fetching Cloudflare IP ranges..."
    CLOUDFLARE_IPS=$(curl -s https://www.cloudflare.com/ips-v4 | tr '\n' ' ')
    
    echo "Fetching Google Bot IP ranges..."
    GOOGLE_IPS="66.249.64.0/19 66.102.0.0/20"
    
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = ${ADMIN_EMAIL}
sendername = Fail2Ban
action = %(action_mwl)s
ignoreip = 127.0.0.1/8 ::1 ${CLOUDFLARE_IPS} ${GOOGLE_IPS}

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log
maxretry = 3

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2

[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/error.log
maxretry = 3

[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = /var/log/apache2/error.log
maxretry = 2

[apache-nohome]
enabled = true
port = http,https
filter = apache-nohome
logpath = /var/log/apache2/error.log
maxretry = 2
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    print_success "Fail2Ban configured with whitelisted IPs"
    fail2ban-client status
    
    mark_step_complete "fail2ban"
}

# 6. AppArmor (After services are configured)
configure_apparmor() {
    if is_step_complete "apparmor"; then
        print_warning "AppArmor already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 6: AppArmor (Mandatory Access Control)"
    
    echo "Loading AppArmor profiles..."
    
    systemctl enable apparmor
    systemctl start apparmor
    
    # Load standard profiles
    aa-enforce /etc/apparmor.d/usr.sbin.sshd 2>/dev/null || true
    aa-enforce /etc/apparmor.d/usr.sbin.apache2 2>/dev/null || true
    
    print_success "AppArmor enabled"
    aa-status
    
    mark_step_complete "apparmor"
}

# 7. ClamAV (Independent antivirus)
configure_clamav() {
    if is_step_complete "clamav"; then
        print_warning "ClamAV already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 7: ClamAV (Antivirus Scanner)"
    
    echo "Updating virus definitions (this may take a few minutes)..."
    
    systemctl stop clamav-freshclam 2>/dev/null || true
    freshclam
    systemctl start clamav-freshclam
    systemctl enable clamav-freshclam
    systemctl enable clamav-daemon
    systemctl start clamav-daemon
    
    # Schedule daily scans
    cat > /etc/cron.daily/clamav-scan <<'EOF'
#!/bin/bash
clamscan -r -i /var/www /home --log=/var/log/clamav/daily-scan.log
EOF
    chmod +x /etc/cron.daily/clamav-scan
    
    print_success "ClamAV configured with daily scans"
    
    mark_step_complete "clamav"
}

# 8. AIDE (File Integrity Monitoring)
configure_aide() {
    if is_step_complete "aide"; then
        print_warning "AIDE already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 8: AIDE (File Integrity Monitoring)"
    
    echo "Initializing AIDE database (this may take several minutes)..."
    
    # Configure AIDE
    cat >> /etc/aide/aide.conf <<EOF

# Auto-Secure custom rules
/usr/local/bin R+b+sha256
/etc R+b+sha256
/var/www/html R+b+sha256
EOF

    aideinit
    
    if [ -f /var/lib/aide/aide.db.new ]; then
        mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
    
    # Schedule daily checks
    cat > /etc/cron.daily/aide-check <<'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Report for $(hostname)" ${ADMIN_EMAIL}
EOF
    chmod +x /etc/cron.daily/aide-check
    
    print_success "AIDE configured with daily integrity checks"
    
    mark_step_complete "aide"
}

# 9. Lynis (Security Auditing)
configure_lynis() {
    if is_step_complete "lynis"; then
        print_warning "Lynis already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 9: Lynis (Security Auditing)"
    
    echo "Running initial security audit..."
    
    lynis audit system --quick --quiet
    
    # Schedule weekly audits
    cat > /etc/cron.weekly/lynis-audit <<EOF
#!/bin/bash
lynis audit system --cronjob | mail -s "Lynis Audit for $(hostname)" ${ADMIN_EMAIL}
EOF
    chmod +x /etc/cron.weekly/lynis-audit
    
    print_success "Lynis configured with weekly audits"
    echo "View full report: cat /var/log/lynis.log"
    
    mark_step_complete "lynis"
}

# 10. Apache Configuration (After all security tools)
configure_apache() {
    if is_step_complete "apache"; then
        print_warning "Apache already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 10: Apache Hardening"
    
    echo "Applying Apache security configurations..."
    
    # Enable security modules
    a2enmod headers rewrite ssl
    
    # Security configuration
    cat > /etc/apache2/conf-available/security-hardening.conf <<EOF
# Hide Apache version
ServerTokens Prod
ServerSignature Off

# Disable directory listing
<Directory />
    Options -Indexes
</Directory>

# Security headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
</IfModule>

# Disable HTTP TRACE
TraceEnable Off

# Limit request size
LimitRequestBody 10485760
EOF

    a2enconf security-hardening
    
    # SSL configuration if enabled
    if prompt_yes_no "Configure SSL/TLS?" "y"; then
        prompt_input "Domain name for SSL" DOMAIN "localhost"
        save_config "DOMAIN" "$DOMAIN"
        
        if prompt_yes_no "Use Let's Encrypt?" "y"; then
            apt-get install -y certbot python3-certbot-apache
            print_warning "Run: certbot --apache -d $DOMAIN to get SSL certificate"
        fi
    fi
    
    systemctl restart apache2
    
    print_success "Apache hardened and restarted"
    
    mark_step_complete "apache"
}

# 11. Automated Updates
configure_auto_updates() {
    if is_step_complete "auto_updates"; then
        print_warning "Auto-updates already configured. Skipping..."
        return 0
    fi
    
    print_header "Step 11: Automatic Security Updates"
    
    if prompt_yes_no "Enable automatic security updates?" "y"; then
        
        cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "${ADMIN_EMAIL}";
EOF

        cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

        systemctl enable unattended-upgrades
        systemctl start unattended-upgrades
        
        print_success "Automatic security updates enabled"
    fi
    
    mark_step_complete "auto_updates"
}

# 12. Final Steps & Restart SSH
finalize_configuration() {
    print_header "Finalizing Configuration"
    
    # Now restart SSH safely
    print_step "Restarting SSH with new configuration..."
    systemctl restart sshd
    print_success "SSH restarted on port $SSH_PORT"
    
    # Create status script
    cat > /usr/local/bin/security-status <<'EOF'
#!/bin/bash
echo "=== Auto-Secure Server Status ==="
echo ""
echo "Firewall:"
ufw status | head -5
echo ""
echo "Fail2Ban:"
fail2ban-client status | head -10
echo ""
echo "AppArmor:"
aa-status | head -5
echo ""
echo "ClamAV:"
systemctl is-active clamav-daemon
echo ""
echo "Services:"
systemctl is-active apache2 ssh fail2ban
EOF
    chmod +x /usr/local/bin/security-status
    
    print_success "Configuration complete!"
    
    print_header "Configuration Summary"
    
    echo "✓ Kernel hardening applied"
    echo "✓ SSH configured on port $SSH_PORT"
    [ "${FWKNOP_ENABLED}" = "true" ] && echo "✓ fwknop port knocking enabled"
    echo "✓ Firewall (UFW) enabled"
    echo "✓ Fail2Ban monitoring SSH and Apache"
    echo "✓ AppArmor profiles loaded"
    echo "✓ ClamAV antivirus scanning daily"
    echo "✓ AIDE file integrity checks"
    echo "✓ Lynis security audits weekly"
    echo "✓ Apache hardened"
    echo ""
    echo "Useful commands:"
    echo "  security-status      - View security tool status"
    echo "  fail2ban-client status - Check banned IPs"
    echo "  lynis audit system   - Run security audit"
    echo "  clamscan -r /var/www - Scan web directory"
    echo ""
    
    if [ "${FWKNOP_ENABLED}" = "true" ]; then
        echo -e "${YELLOW}IMPORTANT: Save your fwknop credentials!${NC}"
        echo "Connect with: fwknop -n $HOSTNAME && ssh -p $SSH_PORT secuser@$HOSTNAME"
    else
        echo "Connect with: ssh -p $SSH_PORT secuser@$HOSTNAME"
    fi
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    initialize_config
    
    configure_kernel_hardening
    configure_ssh
    configure_fwknop
    configure_firewall
    configure_fail2ban
    configure_apparmor
    configure_clamav
    configure_aide
    configure_lynis
    configure_apache
    configure_auto_updates
    finalize_configuration
    
    log "Auto-configuration completed successfully"
}

# Run main function
main "$@"