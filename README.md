# Matrix and Element Web Docker Stack

This repository provides a complete Docker-based configuration for deploying a Matrix homeserver with Element Web and native Element Call support via a self-hosted LiveKit SFU.

## Architecture

The stack consists of the following components:

1. Traefik: Edge router for SSL termination and traffic routing.
2. Matrix Synapse: The homeserver implementation.
3. Element Web: The client interface.
4. LiveKit: Selection Forwarding Unit (SFU) for high-performance video and audio calls.
5. CoTURN: TURN and STUN server to facilitate WebRTC connectivity through restricted networks.
6. PostgreSQL: Database backend for Synapse.

## Prerequisites

To deploy this stack, you need:

1. A Linux server (Ubuntu 22.04 or later recommended) with a public IP.
2. Docker and Docker Compose installed.
3. Three DNS records pointing to your server IP:
    * matrix.yourdomain.com
    * element.yourdomain.com
    * livekit.yourdomain.com

## Getting Started

Follow these steps to initialize and start the services:

1. Clone the repository to your server.
2. Copy the example environment file: `cp env.example .env`
3. Edit the `.env` file and replace the placeholders with your actual domain names and secure passwords.
4. Execute the firewall setup script: `sudo ./setup_firewall.sh`
5. Run the initialization script: `./setup.sh`
    * This script automatically detects your public IPv4 and IPv6 addresses.
    * It generates the required configuration files for Synapse, Element, and LiveKit.
6. Start the stack: `docker compose up -d`

## Management

Use the provided `manage.sh` script to perform common administrative tasks:

* New user registration: `./manage.sh add-user`
* View service logs: `./manage.sh logs`
* Restart the homeserver: `./manage.sh restart`
* Open a shell inside the Synapse container: `./manage.sh bash`

## Connectivity Notes

The stack is configured to support dual-stack (IPv4 and IPv6) environments out of the box. The CoTURN service runs in host network mode to ensure maximum compatibility for WebRTC media relay. If users experience media connection issues, verify that the required UDP ports (3478, 49152 to 49162, and 50000 to 50050) are open in your server provider router settings.

## License

This project is licensed under the MIT License.
    
