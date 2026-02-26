#!/bin/bash
# setup.sh - Infrastructure initialization and configuration generator

echo "WARNING: This script will delete existing data in ./synapse-data and ./db-data."
echo "Press Ctrl+C to abort or Enter to proceed."
read

# Load configuration from .env
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please create one based on env.example."
    exit 1
fi
export $(grep -v '^#' .env | xargs)

# Connectivity check and IP detection
EXTERNAL_IP_V4=$(curl -4 -s https://ifconfig.me || echo "")
EXTERNAL_IP_V6=$(curl -6 -s https://ifconfig.me || echo "")
echo "Detected IPv4: $EXTERNAL_IP_V4"
echo "Detected IPv6: $EXTERNAL_IP_V6"

# Assign primary external IP (prefer IPv4)
EXTERNAL_IP=$EXTERNAL_IP_V4
if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$EXTERNAL_IP_V6
fi

# Persist detected IPs to .env
sed -i "/^EXTERNAL_IP_V4=/d" .env 2>/dev/null || true
sed -i "/^EXTERNAL_IP_V6=/d" .env 2>/dev/null || true
echo "EXTERNAL_IP_V4=$EXTERNAL_IP_V4" >> .env
echo "EXTERNAL_IP_V6=$EXTERNAL_IP_V6" >> .env
sed -i "s/^EXTERNAL_IP=.*/EXTERNAL_IP=$EXTERNAL_IP/" .env 2>/dev/null || echo "EXTERNAL_IP=$EXTERNAL_IP" >> .env

# Cleanup phase
echo "Cleaning up existing environment..."
if [ -n "$COMPOSE_FILE" ]; then
    docker compose down -v
else
    docker compose down -v
fi
rm -rf synapse-data
rm -rf config.json
mkdir -p synapse-data

# Client configuration generation
echo "Generating Element Web configuration..."
rm -rf config.json livekit.yaml element-call-config.json
cat > config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${DOMAIN_MATRIX}",
            "server_name": "${DOMAIN_MATRIX}"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "brand": "Element",
    "jitsi": {
        "preferred_domain": "meet.element.io"
    },
    "element_call": {
        "url": "https://${DOMAIN_CALL}",
        "use_exclusively": true
    },
    "features": {
        "feature_group_calls": true,
        "feature_element_call_video_rooms": true,
        "feature_video_rooms": true
    }
}
EOF

# Synapse initialization
echo "Running Synapse initialization..."
docker run --rm -v "$PWD/synapse-data:/data" \
    -e SYNAPSE_SERVER_NAME=$SYNAPSE_SERVER_NAME \
    -e SYNAPSE_REPORT_STATS=$SYNAPSE_REPORT_STATS \
    matrixdotorg/synapse:latest generate

# Configuration patching
CONFIG_FILE="./synapse-data/homeserver.yaml"
echo "Injecting stack-specific configuration..."

python3 -c "
import sys

config_path = '$CONFIG_FILE'
postgres_password = '$POSTGRES_PASSWORD'
turn_secret = '$TURN_SECRET'
turn_realm = '$TURN_REALM'
external_ip_v4 = '$EXTERNAL_IP_V4'
external_ip_v6 = '$EXTERNAL_IP_V6'
domain_livekit = '$DOMAIN_LIVEKIT'

# Format TURN URIs correctly for both IPv4 and IPv6
turn_uris = []
if external_ip_v4:
    turn_uris.append(f'turn:{external_ip_v4}:3478?transport=udp')
    turn_uris.append(f'turn:{external_ip_v4}:3478?transport=tcp')
if external_ip_v6:
    v6_formatted = f'[{external_ip_v6}]' if ':' in external_ip_v6 and not external_ip_v6.startswith('[') else external_ip_v6
    turn_uris.append(f'turn:{v6_formatted}:3478?transport=udp')
    turn_uris.append(f'turn:{v6_formatted}:3478?transport=tcp')

try:
    with open(config_path, 'r') as f:
        lines = f.readlines()

    new_lines = []
    skip = False
    for line in lines:
        if 'name: sqlite3' in line:
            new_lines.append('  name: psycopg2\n')
            new_lines.append('  args:\n')
            new_lines.append(f'    user: synapse\n')
            new_lines.append(f'    password: \"{postgres_password}\"\n')
            new_lines.append(f'    database: synapse\n')
            new_lines.append(f'    host: db\n')
            new_lines.append(f'    cp_min: 5\n')
            new_lines.append(f'    cp_max: 10\n')
            skip = True
            continue
        if skip and 'database:' in line and 'homeserver.db' in line:
            skip = False
            continue
        if not skip:
            new_lines.append(line)

    content = ''.join(new_lines)
    if '# TURN Configuration' in content:
        content = content.split('# TURN Configuration')[0]
    
    turn_config = '\n# TURN service configuration\nturn_uris:\n'
    for uri in turn_uris:
        turn_config += f'  - \"{uri}\"\n'
    
    turn_config += f'turn_shared_secret: \"{turn_secret}\"\nturn_user_lifetime: \"86400000\"\nturn_allow_guests: true\n'
    content += turn_config
    
    # Enable MSCs for Element Call
    content += '\nexperimental_features:\n  msc3401_enabled: true\n  msc3843_enabled: true\n  msc4143_enabled: true\n'
    content += '\nmatrix_rtc:\n  transports:\n    - type: livekit\n      livekit_service_url: \"https://{domain_livekit}\"\n'
    content += '\n# Guest access for public video conference links\nallow_guest_access: true\n'

    with open(config_path, 'w') as f:
        f.write(content)
except Exception as e:
    print(f'Error patching configuration: {e}')
    sys.exit(1)
"

# Discovery configuration
echo "Creating discovery endpoints (.well-known)..."
mkdir -p .well-known/matrix
cat > .well-known/matrix/server <<EOF
{
    "m.server": "${DOMAIN_MATRIX}:443"
}
EOF
cat > .well-known/matrix/client <<EOF
{
    "m.homeserver": {
        "base_url": "https://${DOMAIN_MATRIX}"
    },
    "m.identity_server": {
        "base_url": "https://vector.im"
    },
    "org.matrix.msc4143.rtc_foci": [
        {
            "type": "livekit",
            "livekit_service_url": "https://${DOMAIN_LIVEKIT}"
        }
    ]
}
EOF

# SFU configuration
echo "Generating LiveKit configuration..."
cat > livekit.yaml <<EOF
log_level: info
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50050
  node_ip: "${EXTERNAL_IP}"
  use_external_ip: false
room:
  auto_create: false
keys:
  "${LIVEKIT_API_KEY}": "${LIVEKIT_API_SECRET}"
EOF

# Element Call Standalone configuration
echo "Generating Element Call configuration..."
cat > element-call-config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${DOMAIN_MATRIX}",
            "server_name": "${DOMAIN_MATRIX}"
        }
    },
    "livekit": {
        "livekit_service_url": "https://${DOMAIN_LIVEKIT}"
    },
    "brand": "Element Call"
}
EOF

# Permissions
echo "Applying filesystem permissions..."
sudo chown -R 991:991 synapse-data 2>/dev/null || true
sudo chown -R $USER:$USER .well-known 2>/dev/null || true

# Virtual Host deployment
echo "Updating Nginx configuration templates..."
for f in nginx-matrix.conf nginx-element.conf nginx-livekit.conf nginx-element-call.conf; do
    if [ -f "$f" ]; then
        sed -i "s/matrix.example.com/${DOMAIN_MATRIX}/g" "$f" 2>/dev/null
        sed -i "s/element.example.com/${DOMAIN_ELEMENT}/g" "$f" 2>/dev/null
        sed -i "s/livekit.example.com/${DOMAIN_LIVEKIT}/g" "$f" 2>/dev/null
        sed -i "s/call.example.com/${DOMAIN_CALL}/g" "$f" 2>/dev/null
    fi
done

echo "Deployment preparation finished."
if [[ "$COMPOSE_FILE" == *"element-call/call.yml"* ]]; then
    echo "Element Call override is ENABLED."
else
    echo "Element Call override is DISABLED."
fi
echo "Execute 'docker compose up -d' to start the services."
