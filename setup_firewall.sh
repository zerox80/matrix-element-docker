#!/bin/bash
# setup_firewall.sh - Automated firewall configuration for Matrix/Element stack

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Initializing firewall configuration...${NC}"

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
echo -e "${GREEN}Allowing CoTURN (Ports 3478, 5349 - TCP and UDP)...${NC}"
sudo ufw allow 3478/tcp
sudo ufw allow 3478/udp
sudo ufw allow 5349/tcp
sudo ufw allow 5349/udp

echo -e "${GREEN}Allowing CoTURN Media Range (49152-49162 UDP)...${NC}"
sudo ufw allow 49152:49162/udp

# LiveKit (SFU) Ports
echo -e "${GREEN}Allowing LiveKit Signaling (7880/tcp, 7881/tcp)...${NC}"
sudo ufw allow 7880/tcp
sudo ufw allow 7881/tcp

echo -e "${GREEN}Allowing LiveKit Media Range (50000-50050 UDP)...${NC}"
sudo ufw allow 50000:50050/udp

# Activation
echo -e "${YELLOW}Enabling UFW...${NC}"
echo "y" | sudo ufw enable

echo "Firewall is configured and active."
sudo ufw status
