#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root: sudo ./fix-coturn-letsencrypt-acl.sh" >&2
  exit 1
fi

if ! command -v setfacl >/dev/null 2>&1; then
  echo "Missing setfacl. Install ACL support first:" >&2
  echo "  apt update && apt install -y acl" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Missing .env in the current directory." >&2
  exit 1
fi

domain_livekit="$(
  grep -E '^DOMAIN_LIVEKIT=' .env | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
)"

if [[ -z "${domain_livekit}" ]]; then
  echo "DOMAIN_LIVEKIT is missing from .env." >&2
  exit 1
fi

live_dir="/etc/letsencrypt/live/${domain_livekit}"
archive_dir="/etc/letsencrypt/archive/${domain_livekit}"
fullchain="${live_dir}/fullchain.pem"
privkey="${live_dir}/privkey.pem"

if [[ ! -e "${fullchain}" || ! -e "${privkey}" ]]; then
  echo "LetsEncrypt certificate files were not found for ${domain_livekit}." >&2
  echo "Expected:" >&2
  echo "  ${fullchain}" >&2
  echo "  ${privkey}" >&2
  exit 1
fi

fullchain_target="$(readlink -f "${fullchain}")"
privkey_target="$(readlink -f "${privkey}")"

setfacl -m u:65534:rx /etc/letsencrypt
setfacl -m u:65534:rx /etc/letsencrypt/live
setfacl -m u:65534:rx "${live_dir}"
setfacl -m u:65534:rx /etc/letsencrypt/archive
setfacl -m u:65534:rx "${archive_dir}"
setfacl -m u:65534:r "${fullchain_target}"
setfacl -m u:65534:r "${privkey_target}"

echo "Granted coturn UID 65534 read access to ${domain_livekit} certificate files."
echo "Next:"
echo "  docker compose restart coturn"
echo "  ss -lntup | grep ':5349'"
