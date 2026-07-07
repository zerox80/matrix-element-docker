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
    * It is destructive and intended for initial setup only. If existing Synapse or database data is detected, it aborts unless you explicitly confirm with `DELETE_EXISTING_DATA`.
6. Start the stack: `docker compose up -d`

## Element Call

Element Call is enabled through the optional Compose override at `element-call/call.yml`. On Linux and macOS, set this in `.env`:

```env
COMPOSE_FILE=docker-compose.yml:element-call/call.yml
```

Then validate that Compose includes the Element Call services:

```bash
docker compose config --services
```

The output should include:

```text
livekit
lk-jwt-service
element-call
```

You can also start the stack with explicit Compose files instead of using `COMPOSE_FILE`:

```bash
docker compose -f docker-compose.yml -f element-call/call.yml up -d
```

Windows PowerShell users may need semicolon syntax in `COMPOSE_FILE` or the explicit `-f` flags above, depending on their Docker Compose environment.

## Image Versions

Traefik is pinned through `TRAEFIK_VERSION` in `.env`. Some other images still use `latest` by default for compatibility with the current stack. For production deployments, review and pin those images to tested versions before upgrading so container updates do not change behavior unexpectedly.

## Validation

After setup, these commands are useful for checking the generated Compose configuration and LiveKit container:

```bash
docker compose config --services
docker compose config | grep -A10 -B3 '/etc/livekit.yaml'
docker compose logs --tail=100 livekit
docker ps --filter name=livekit
```

The generated Compose config should mount the repository root `livekit.yaml` file to `/etc/livekit.yaml`, and the repository root `element-call-config.json` file to `/app/config.json`.

## Troubleshooting

### LiveKit reports `read /etc/livekit.yaml: is a directory`

This error means Docker mounted a directory at `/etc/livekit.yaml` instead of the generated `livekit.yaml` config file. Check the merged Compose config and the running container mounts:

```bash
docker compose config | grep -A10 -B3 '/etc/livekit.yaml'
docker inspect livekit --format '{{range .Mounts}}{{println .Source "->" .Destination "type=" .Type}}{{end}}'
file livekit.yaml
```

If `livekit.yaml` is a file in the repository root and the Compose config points to it, recreate the LiveKit container so Docker replaces the bad mount:

```bash
docker compose stop livekit && docker compose rm -f livekit && docker compose up -d livekit
```

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
    
