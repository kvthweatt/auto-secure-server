#!/bin/bash
# Auto-Secure Server - One Click Deployment

set -e

echo "=========================================="
echo "Auto-Secure Server Deployment"
echo "Enterprise Security on a $6 Droplet"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Check for Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}docker-compose not found, using docker compose plugin...${NC}"
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Create necessary directories
echo -e "${GREEN}Creating directory structure...${NC}"
mkdir -p {web,logs,data,backups,ssl,configs}

# Create sample web page
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Auto-Secure Server</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .security-badge { background: #4CAF50; color: white; padding: 5px 10px; border-radius: 3px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
        .stat-card { background: #f5f5f5; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>🚀 Auto-Secure Server</h1>
    <p><span class="security-badge">SECURE</span> Your server is protected by enterprise-grade security tools.</p>
    
    <div class="stats">
        <div class="stat-card">
            <h3>🛡️ Security Layers</h3>
            <p>12+ tools working together</p>
        </div>
        <div class="stat-card">
            <h3>💰 Cost</h3>
            <p>$6/month vs $25,000+/year</p>
        </div>
        <div class="stat-card">
            <h3>⚡ Performance</h3>
            <p>~300MB RAM, 1% CPU</p>
        </div>
    </div>
    
    <h2>Security Tools Running:</h2>
    <ul>
        <li>Kernel Hardening</li>
        <li>Fail2Ban with Cloudflare/Google whitelisting</li>
        <li>ClamAV Malware Scanner</li>
        <li>AIDE File Integrity Monitoring</li>
        <li>Lynis Security Auditing</li>
        <li>AppArmor Profiles</li>
        <li>And 6+ more tools...</li>
    </ul>
    
    <p><a href="https://github.com/yourusername/auto-secure-server" target="_blank">View on GitHub</a></p>
</body>
</html>
EOF

# Create environment file
cat > .env << 'EOF'
# Auto-Secure Server Environment Variables
COMPOSE_PROJECT_NAME=auto-secure
TZ=UTC
ADMIN_EMAIL=admin@localhost
ENABLE_SSL=false
MYSQL_ROOT_PASSWORD=ChangeMe123!
MYSQL_DATABASE=secureapp
MYSQL_USER=secureuser
MYSQL_PASSWORD=SecurePass123!
EOF

echo -e "${GREEN}Building Auto-Secure Server image...${NC}"
$DOCKER_COMPOSE -f docker/docker-compose.yml build

echo -e "${GREEN}Starting containers...${NC}"
$DOCKER_COMPOSE -f docker/docker-compose.yml up -d

echo -e "${GREEN}Waiting for services to start...${NC}"
sleep 10

echo -e "${GREEN}Running security verification...${NC}"
docker exec auto-secure-dev /usr/local/bin/secure-boot.sh

echo ""
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo ""
echo "=========================================="
echo "Access your secure server:"
echo "  Website: http://localhost:8080"
echo "  SSH:     localhost:2222 (user: secuser)"
echo "  phpMyAdmin: http://localhost:8081"
echo ""
echo "Security Dashboard:"
echo "  Fail2Ban status: docker exec auto-secure-dev fail2ban-client status"
echo "  Security scan:   docker exec auto-secure-dev lynis audit system"
echo "  View logs:       docker logs auto-secure-dev"
echo ""
echo "Stop services:     docker-compose down"
echo "Rebuild:           docker-compose build --no-cache"
echo "=========================================="