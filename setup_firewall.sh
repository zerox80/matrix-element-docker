#!/bin/bash
# setup_firewall.sh - Automated firewall configuration for Matrix/Element stack

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Initializing firewall configuration...${NC}"

ENABLE_UDP=false
if [ "$1" = "--with-udp" ]; then
    ENABLE_UDP=true
elif [ -f .env ]; then
    COMPOSE_FILE_VALUE=$(grep -E '^COMPOSE_FILE=' .env | tail -n1 | cut -d= -f2-)
    if echo "$COMPOSE_FILE_VALUE" | grep -q 'element-call/udp.yml'; then
        ENABLE_UDP=true
    fi
fi

# SSH Access
echo -e "${GREEN}Allowing SSH (Port 22)...${NC}"
sudo ufw allow ssh

# Web and Federation Ports
echo -e "${GREEN}Allowing HTTP and HTTPS (Ports 80, 443)...${NC}"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo -e "${GREEN}Allowing Matrix Federation (Port 8448)...${NC}"
sudo ufw allow 8448/tcp

# CoTURN (VoIP Relay) Ports
echo -e "${GREEN}Allowing CoTURN TCP/TLS fallback ports (3478/tcp, 5349/tcp)...${NC}"
sudo ufw allow 3478/tcp
sudo ufw allow 5349/tcp

# LiveKit (SFU) Ports
echo -e "${GREEN}Allowing LiveKit Signaling (7880/tcp, 7881/tcp)...${NC}"
sudo ufw allow 7880/tcp
sudo ufw allow 7881/tcp

if [ "$ENABLE_UDP" = true ]; then
    echo -e "${GREEN}UDP mode enabled: allowing CoTURN and LiveKit UDP media ports...${NC}"
    sudo ufw allow 3478/udp
    sudo ufw allow 5349/udp
    sudo ufw allow 49152:49162/udp
    sudo ufw allow 50000:50050/udp
else
    echo -e "${YELLOW}UDP mode disabled. Skipping 3478/udp, 5349/udp, 49152-49162/udp, and 50000-50050/udp.${NC}"
    echo -e "${YELLOW}Run './setup_firewall.sh --with-udp' or enable element-call/udp.yml in COMPOSE_FILE to open UDP media ports.${NC}"
fi

# Activation
echo -e "${YELLOW}Enabling UFW...${NC}"
echo "y" | sudo ufw enable

echo "Firewall is configured and active."
sudo ufw status
