#!/bin/bash
# manage.sh - Administrative utility for Synapse

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function show_usage() {
    echo -e "Usage: ./manage.sh [command]"
    echo ""
    echo "Commands:"
    echo "  add-user   - Create a new Matrix user"
    echo "  bash       - Open an interactive shell inside the Synapse container"
    echo "  logs       - Follow Synapse logs"
    echo "  restart    - Restart the Synapse service"
    echo "  help       - Show this help message"
}

case "$1" in
    add-user)
        echo -e "${GREEN}Starting user registration process...${NC}"
        echo -e "Ensure Synapse is fully started (check: docker compose logs synapse)"
        docker exec -it synapse register_new_matrix_user -c /data/homeserver.yaml http://127.0.0.1:8008
        ;;
    bash)
        echo -e "${GREEN}Opening container shell...${NC}"
        docker exec -it synapse bash
        ;;
    logs)
        docker compose logs -f synapse
        ;;
    restart)
        echo -e "${GREEN}Restarting Synapse...${NC}"
        docker compose restart synapse
        ;;
    help|*)
        show_usage
        ;;
esac
