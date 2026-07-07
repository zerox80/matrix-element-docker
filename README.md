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

## Enabling Element Call

Element Call is provided by the optional Compose override in `element-call/call.yml`.
Enable it in `.env` on Linux/macOS with:

```bash
COMPOSE_FILE=docker-compose.yml:element-call/call.yml
```

Windows PowerShell users may need semicolon syntax or explicit `-f` flags depending on their Docker Compose environment.

Validate that the override is active:

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

For an existing server checkout, update and restart with:

```bash
git pull
docker compose build
docker compose down
docker compose up -d
```

## Image Versions

Traefik is pinned through `TRAEFIK_VERSION` in `.env`. Some other images still use `latest` by default for compatibility with the current stack. For production deployments, review and pin those images to tested versions before upgrading so container updates do not change behavior unexpectedly.

## Validation

After setup, these commands are useful for checking the generated Compose configuration and LiveKit container:

```bash
docker compose config --services
docker compose config | grep -A20 -B5 'LIVEKIT_CONFIG'
docker compose logs --tail=100 coturn
docker compose logs --tail=100 livekit
docker ps --filter name=livekit
ss -lntup | grep -E ':(3478|5349|7880|7881|50000|49152)'
```

`coturn` should listen on `3478` and `5349`, and LiveKit join responses should advertise a TURN/TLS server for `${DOMAIN_LIVEKIT}:5349`.

## Troubleshooting

### LiveKit reports `read /etc/livekit.yaml: is a directory`

This error means Docker mounted a directory at `/etc/livekit.yaml` instead of the generated `livekit.yaml` config file. The current stack configures LiveKit through `LIVEKIT_CONFIG` to avoid stale or mis-mounted `livekit.yaml` files, but older deployments can still hit this.

Check the merged Compose config and the running container mounts:

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

The stack is configured to support dual-stack (IPv4 and IPv6) environments out of the box. The CoTURN service runs in host network mode to ensure maximum compatibility for WebRTC media relay.

For restrictive networks, LiveKit advertises TURN/TLS on `${DOMAIN_LIVEKIT}:5349` in addition to direct UDP/TCP candidates. CoTURN expects readable certificates at:

```text
/etc/letsencrypt/live/${DOMAIN_LIVEKIT}/fullchain.pem
/etc/letsencrypt/live/${DOMAIN_LIVEKIT}/privkey.pem
```

Verify that the required ports are open in your server provider firewall:

```text
3478/tcp and 3478/udp
5349/tcp
49152-49162/udp
7880/tcp and 7881/tcp
50000-50050/udp
```

Port `443/tcp` is usually already used by nginx or Traefik. Use `5349/tcp` for TURN/TLS unless you have a separate IP or a dedicated TURN hostname that can own `443/tcp`.

## Validation

After changing the stack, run:

```bash
docker compose config --services
docker compose config | grep -A20 -B5 'LIVEKIT_CONFIG'
docker compose logs --tail=100 coturn
docker compose logs --tail=100 livekit
docker ps --filter name=livekit
ss -lntup | grep -E ':(3478|5349|7880|7881|50000|49152)'
```

`coturn` should listen on `3478` and `5349`, and LiveKit join responses should advertise a TURN/TLS server for `${DOMAIN_LIVEKIT}:5349`.

## Troubleshooting

### `read /etc/livekit.yaml: is a directory`

This means Docker mounted a directory instead of the intended LiveKit config file. The current stack configures LiveKit through `LIVEKIT_CONFIG` to avoid stale or mis-mounted `livekit.yaml` files, but older deployments can still hit this.

Inspect the generated Compose config and container mounts:

```bash
docker compose config | grep -A10 -B3 '/etc/livekit.yaml'
docker inspect livekit --format '{{range .Mounts}}{{println .Source "->" .Destination "type=" .Type}}{{end}}'
file livekit.yaml
docker compose stop livekit && docker compose rm -f livekit && docker compose up -d livekit
```

### Calls stay on waiting for media

If messages arrive but calls hang, check whether the remote user appears in both JWT and LiveKit logs:

```bash
docker compose logs -f lk-jwt-service livekit | grep -Ei 'majid|LiveKit room|participant|ice|dtls|timeout|error|connection'
```

If the user reaches `lk-jwt-service` but never appears as a LiveKit participant, verify TURN/TLS on `5349/tcp` and the provider firewall first.

## License

This project is licensed under the MIT License.
    
