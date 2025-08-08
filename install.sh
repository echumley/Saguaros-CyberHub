#!/usr/bin/env bash
set -euo pipefail

# =========================
#   Path & State
# =========================
STATE_DIR="/var/lib/cyberhub-installer"
STATE_FILE="${STATE_DIR}/state.json"
CFG_FILE="/etc/cyberhub/installer.yaml"
SECRETS_FILE="/etc/cyberhub/secrets.env"
LOG_FILE="/var/log/cyberhub-installer.log"

mkdir -p "$(dirname "$CFG_FILE")" "$STATE_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

PLAN_MODE="false"
RESUME_MODE="false"

# =========================
#   Helper functions
# =========================
require() { command -v "$1" >/dev/null || { echo "Need $1"; exit 1; }; }
json_get() { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo ""; }
json_set() {
  local key="$1" value="$2"
  if [[ ! -s "$STATE_FILE" ]]; then echo '{}' > "$STATE_FILE"; fi
  tmp=$(mktemp)
  jq --arg v "$value" "$key = \$v" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =========================
#   Safety: tmux session
# =========================
ensure_tmux() {
  if [[ -z "${TMUX:-}" ]]; then
    echo "[INFO] Not in tmux — starting a persistent tmux session 'cyberhub-install'"
    require tmux
    tmux new-session -s cyberhub-install "$0" "$@"
    exit 0
  fi
}

# =========================
#   CLI args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume) RESUME_MODE="true"; shift ;;
    --plan) PLAN_MODE="true"; shift ;;
    --help)
      echo "Usage: $0 [--plan] [--resume]"
      exit 0
      ;;
    *) shift ;;
  esac
done

# =========================
#   First-run wizard
# =========================
first_run_wizard() {
  require whiptail
  TITLE="CyberHub Installer"

  ENV=$(whiptail --title "$TITLE" --nocancel --menu "Select environment" 15 60 4 \
      "dev" "Development" \
      "stage" "Staging" \
      "prod" "Production" 3>&1 1>&2 2>&3)

  DOMAIN=$(whiptail --title "$TITLE" --nocancel --inputbox "Base domain (e.g. cyberhub.local)" 10 60 "" 3>&1 1>&2 2>&3)

  PVE_HOSTNAME=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox hostname (FQDN)" 10 60 "pve.${DOMAIN}" 3>&1 1>&2 2>&3)
  MGMT_IFACE=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt interface" 10 60 "eno1" 3>&1 1>&2 2>&3)
  MGMT_CIDR=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt CIDR" 10 60 "" 3>&1 1>&2 2>&3)
  MGMT_GW=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox gateway" 10 60 "" 3>&1 1>&2 2>&3)

  BACKEND=$(whiptail --title "$TITLE" --nocancel --menu "Secrets backend" 15 60 3 \
      "vault" "HashiCorp Vault" \
      "sops"  "Mozilla SOPS + age" \
      "env"   "Local .env" 3>&1 1>&2 2>&3)

  MODULE_CHOICES=$(whiptail --title "$TITLE" --separate-output --checklist "Select modules" 20 70 10 \
      "hub" "Core web portal" ON \
      "cybercore" "CyberCore orchestration" ON \
      "cyberlabs" "Virtualization env" OFF \
      "crucible" "CTF range" OFF \
      "university" "Moodle LMS" OFF \
      "library" "Resource library" OFF \
      "wiki" "Cyber Wiki" OFF \
      "archive" "Malware/data archive" OFF \
      "forge" "Malware dev sandbox" OFF 3>&1 1>&2 2>&3) || true
  MODULES=$(echo "$MODULE_CHOICES" | tr '\n' ',' | sed 's/,$//')

  cat > "$CFG_FILE" <<YAML
env: "$ENV"
domain: "$DOMAIN"
pve:
  hostname: "$PVE_HOSTNAME"
  mgmt_iface: "$MGMT_IFACE"
  mgmt_cidr: "$MGMT_CIDR"
  mgmt_gw: "$MGMT_GW"
secrets_backend: "$BACKEND"
modules: [$(echo "$MODULES" | sed 's/,/, /g' | sed 's/\([^,][^,]*\)/"\1"/g')]
YAML
  chmod 644 "$CFG_FILE"

  if [[ ! -f "$SECRETS_FILE" ]]; then
    touch "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
    cat >> "$SECRETS_FILE" <<ENV
# Backend secrets config
# VAULT_ADDR=
# VAULT_NAMESPACE=
# VAULT_TOKEN=
# SOPS_AGE_KEY_FILE=
ENV
  fi

  json_set '.first_run_done' 'true'
}

# =========================
#   Proxmox install
# =========================
install_proxmox_on_debian() {
  if dpkg -s pve-manager >/dev/null 2>&1; then
    echo "[Proxmox] Already installed."
    json_set '.pve.installed' 'true'
    return
  fi

  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
    echo "Debian 12 required."
    exit 1
  fi

  require curl; require gpg; require yq
  HOSTNAME=$(yq -r '.pve.hostname' "$CFG_FILE")
  if ! grep -q "$HOSTNAME" /etc/hosts; then
    IP=$(yq -r '.pve.mgmt_cidr' "$CFG_FILE" | cut -d'/' -f1)
    echo "$IP $HOSTNAME ${HOSTNAME%%.*}" >> /etc/hosts
  fi
  hostnamectl set-hostname "$HOSTNAME"

  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list
  curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
    -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

  apt-get update
  apt-get install -y pve-kernel-6.8 proxmox-ve postfix open-iscsi

  # network
  IFACE=$(yq -r '.pve.mgmt_iface' "$CFG_FILE")
  CIDR=$(yq -r '.pve.mgmt_cidr' "$CFG_FILE")
  GW=$(yq -r '.pve.mgmt_gw' "$CFG_FILE")
  cat >/etc/network/interfaces <<IFC
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
  address ${CIDR}
  gateway ${GW}
IFC

  systemctl enable --now iscsid || true
  json_set '.pve.installed' 'true'
  json_set '.pve.reboot_required' 'true'
}

# =========================
#   Post-Proxmox tweaks
# =========================
proxmox_postinstall_tweaks() {
  sed -i 's|^deb https://enterprise.proxmox.com/#|# &|' /etc/apt/sources.list.d/pve-enterprise.list || true
  echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-intel.conf || true
  echo "options kvm_amd nested=1"   > /etc/modprobe.d/kvm-amd.conf || true
  update-initramfs -u || true
  modprobe kvm_intel || modprobe kvm_amd || true
}

# =========================
#   Secrets backend loader
# =========================
fetch_secrets() {
  BACKEND=$(yq -r '.secrets_backend' "$CFG_FILE")
  case "$BACKEND" in
    vault) require vault; require jq; source "$SECRETS_FILE" ;;
    sops) require sops; require age; source "$SECRETS_FILE" ;;
    env) source "$SECRETS_FILE" ;;
  esac
}

# =========================
#   Terraform/Ansible/Compose runners
# =========================
terraform_run() {
  local dir="$1"
  pushd "$dir" >/dev/null
  terraform init -upgrade
  if [[ "$PLAN_MODE" == "true" ]]; then
    terraform plan -var "env=$(yq -r '.env' "$CFG_FILE")" -var "domain=$(yq -r '.domain' "$CFG_FILE")"
  else
    terraform apply -auto-approve -var "env=$(yq -r '.env' "$CFG_FILE")" -var "domain=$(yq -r '.domain' "$CFG_FILE")"
  fi
  popd >/dev/null
}

ansible_run() {
  local inventory="$1" playbook="$2"
  pushd ansible >/dev/null
  if [[ "$PLAN_MODE" == "true" ]]; then
    ansible-playbook -i "$inventory" "$playbook" -e "@${CFG_FILE}" --check
  else
    ansible-playbook -i "$inventory" "$playbook" -e "@${CFG_FILE}"
  fi
  popd >/dev/null
}

compose_run() {
  local dir="$1"
  if [[ "$PLAN_MODE" == "true" ]]; then
    echo "[PLAN] Would run docker compose in $dir"
    return
  fi
  pushd "$dir" >/dev/null
  docker compose --env-file .env.runtime up -d
  popd >/dev/null
}

# =========================
#   Install CyberCore + Hub
# =========================
install_cybercore_and_hub() {
  terraform_run terraform/core
  ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" site_core.yml
  compose_run compose/hub
  json_set '.core.installed' 'true'
}

# =========================
#   Install selected modules
# =========================
install_modules() {
  IFS=',' read -ra MODS <<< "$(yq -r '.modules | join(",")' "$CFG_FILE")"
  for m in "${MODS[@]}"; do
    case "$m" in
      cyberlabs)
        terraform_run terraform/cyberlabs
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" cyberlabs.yml
        compose_run compose/cyberlabs
        ;;
      crucible)
        terraform_run terraform/crucible
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" crucible.yml
        compose_run compose/crucible
        ;;
      # add other modules similarly...
    esac
  done
  json_set '.modules.installed' 'true'
}

# =========================
#   Main
# =========================
ensure_tmux "$@"

if [[ "$RESUME_MODE" != "true" && "$(json_get '.first_run_done')" != "true" ]]; then
  require jq; require yq
  first_run_wizard
fi

if [[ "$(json_get '.pve.installed')" != "true" ]]; then
  install_proxmox_on_debian
  echo "[INFO] Reboot required after Proxmox install. Please reboot and re-run with --resume"
  exit 0
fi

proxmox_postinstall_tweaks
fetch_secrets

if [[ "$(json_get '.core.installed')" != "true" ]]; then
  install_cybercore_and_hub
fi

if [[ "$(json_get '.modules.installed')" != "true" ]]; then
  install_modules
fi

echo "✅ CyberHub install complete (plan mode: $PLAN_MODE)"