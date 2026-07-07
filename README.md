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
6. If Element Call is enabled and you use LetsEncrypt certificates for TURN/TLS, apply the CoTURN certificate ACLs after the certificates exist and before the first start:

    ```bash
    sudo apt update && sudo apt install -y acl
    sudo ./fix-coturn-letsencrypt-acl.sh
    ```

7. Start the stack: `docker compose up -d`

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

Traefik is pinned through `TRAEFIK_VERSION` in `.env`. Use Traefik `v3.6.1` or newer with Docker Engine 29+, otherwise Traefik's Docker provider can fail with `client version 1.24 is too old` and all label-based routes may return `404`.

Some other images still use `latest` by default for compatibility with the current stack. For production deployments, review and pin those images to tested versions before upgrading so container updates do not change behavior unexpectedly.

## Logging

Traefik logs at `INFO` by default. For temporary routing debugging, set this in `.env` and recreate Traefik:

```env
TRAEFIK_LOG_LEVEL=DEBUG
```

```bash
docker compose up -d --force-recreate traefik
```

Set it back to `INFO` when finished and recreate Traefik again. `DEBUG` logs every routed request and can become very noisy on an active Matrix server.

## Reverse Proxy Client IPs

This stack assumes an optional host-level reverse proxy such as nginx can sit in front of Traefik and proxy to the loopback-bound Traefik ports. Traefik trusts forwarded headers from `TRAEFIK_TRUSTED_PROXY_IPS`, which defaults to `127.0.0.1/32,172.16.0.0/12`. The Docker bridge proxy can appear as a `172.x.x.x` source even when nginx connects to `127.0.0.1`, so this allows Synapse to store the real client IP from `X-Forwarded-For` instead of the Docker gateway IP.

If Traefik is exposed directly to the public internet without a host reverse proxy, restrict `TRAEFIK_TRUSTED_PROXY_IPS` to only the proxy IPs you actually control.

To check what Synapse records for recent clients:

```bash
docker exec -it synapse_db psql -U synapse -d synapse -c "SELECT user_id, ip, user_agent, to_timestamp(last_seen/1000) AS last_seen FROM user_ips ORDER BY last_seen DESC LIMIT 10;"
```

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

The `coturn/coturn` image runs the TURN process as UID `65534` (`nobody`). LetsEncrypt private keys are often only readable by root, so TURN/TLS can silently fail to listen on `5349/tcp` unless that UID can traverse and read the certificate files.

On a fresh server, run this after certificates exist and before the first `docker compose up -d`. Do not run it before certificate creation; it fails safely when the LetsEncrypt files are missing.

```bash
sudo apt update && sudo apt install -y acl
sudo ./fix-coturn-letsencrypt-acl.sh
```

If CoTURN is already running, restart or recreate it after applying the ACLs because the running process may already have skipped the TLS listener:

```bash
docker compose restart coturn
```

The ACL script applies the same access as these manual commands:

```bash
setfacl -m u:65534:rx /etc/letsencrypt
setfacl -m u:65534:rx /etc/letsencrypt/live
setfacl -m u:65534:rx /etc/letsencrypt/live/${DOMAIN_LIVEKIT}
setfacl -m u:65534:rx /etc/letsencrypt/archive
setfacl -m u:65534:rx /etc/letsencrypt/archive/${DOMAIN_LIVEKIT}
setfacl -m u:65534:r /etc/letsencrypt/archive/${DOMAIN_LIVEKIT}/fullchain*.pem
setfacl -m u:65534:r /etc/letsencrypt/archive/${DOMAIN_LIVEKIT}/privkey*.pem
```

Verify from inside the container:

```bash
docker exec coturn sh -lc "test -r /etc/letsencrypt/live/${DOMAIN_LIVEKIT}/fullchain.pem && echo cert-ok || echo cert-bad; test -r /etc/letsencrypt/live/${DOMAIN_LIVEKIT}/privkey.pem && echo key-ok || echo key-bad"
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

### Traefik returns `404 page not found` for all services

If every domain returns `404` and Traefik logs repeat this Docker provider error:

```text
client version 1.24 is too old. Minimum supported API version is 1.40
```

Upgrade Traefik to `v3.6.1` or newer and recreate the container:

```bash
sed -i 's/^TRAEFIK_VERSION=.*/TRAEFIK_VERSION=v3.6.1/' .env
docker compose pull traefik
docker compose up -d --force-recreate traefik
docker compose logs --tail=80 traefik | grep -Ei 'docker|error|provider|router'
```

The Compose file intentionally does not set `DOCKER_API_VERSION` or `DOCKER_CLIENT_API_VERSION`; Traefik should negotiate with the Docker daemon itself.

### CoTURN does not listen on `5349/tcp`

If `3478/tcp` and `3478/udp` work but `5349/tcp` is missing:

```bash
ss -lntup | grep -E ':(3478|5349)'
docker compose logs --tail=120 coturn
docker exec coturn sh -lc "test -r /etc/letsencrypt/live/${DOMAIN_LIVEKIT}/fullchain.pem && echo cert-ok || echo cert-bad; test -r /etc/letsencrypt/live/${DOMAIN_LIVEKIT}/privkey.pem && echo key-ok || echo key-bad"
```

If the container prints `cert-bad` or `key-bad`, apply the LetsEncrypt ACL commands from the Connectivity Notes section and recreate CoTURN:

```bash
docker compose up -d --force-recreate coturn
ss -lntup | grep ':5349'
```

## License

This project is licensed under the MIT License.
    
