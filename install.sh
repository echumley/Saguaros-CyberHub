#!/usr/bin/env bash
set -euo pipefail

# =========================
#   Root check
# =========================
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# =========================
#   Paths & State
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
#   Helpers
# =========================
require() { command -v "$1" >/dev/null || { echo "Need '$1' installed. Aborting."; exit 1; }; }
json_get() { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo ""; }
json_set() {
  local key="$1" value="$2"
  if [[ ! -s "$STATE_FILE" ]]; then echo '{}' > "$STATE_FILE"; fi
  local tmp
  tmp=$(mktemp)
  jq --arg v "$value" "$key = \$v" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =========================
#   CLI args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume) RESUME_MODE="true"; shift ;;
    --plan) PLAN_MODE="true"; shift ;;
    --help)
      cat <<USAGE
Usage: $0 [--plan] [--resume]

--plan    Dry run: Terraform 'plan', Ansible '--check', skip docker 'up'
--resume  Skip first-run wizard; continue from state.json
USAGE
      exit 0
      ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# =========================
#   First-run wizard
# =========================
first_run_wizard() {
  require whiptail
  require jq
  require yq

  local TITLE="CyberHub Installer"

  local ENV DOMAIN PVE_HOSTNAME MGMT_IFACE MGMT_CIDR MGMT_GW BACKEND MODULE_CHOICES MODULES

  ENV=$(whiptail --title "$TITLE" --nocancel --menu "Select environment" 15 60 4 \
      "dev" "Development" \
      "stage" "Staging" \
      "prod" "Production" 3>&1 1>&2 2>&3)

  DOMAIN=$(whiptail --title "$TITLE" --nocancel --inputbox "Base domain (e.g. cyberhub.local or example.edu)" 10 60 "" 3>&1 1>&2 2>&3)

  PVE_HOSTNAME=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox hostname (FQDN)" 10 60 "pve.${DOMAIN}" 3>&1 1>&2 2>&3)
  MGMT_IFACE=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt interface (e.g. eno1)" 10 60 "eno1" 3>&1 1>&2 2>&3)
  MGMT_CIDR=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt CIDR (e.g. 10.0.0.10/24)" 10 60 "" 3>&1 1>&2 2>&3)
  MGMT_GW=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox default gateway (e.g. 10.0.0.1)" 10 60 "" 3>&1 1>&2 2>&3)

  BACKEND=$(whiptail --title "$TITLE" --nocancel --menu "Secrets backend" 15 60 3 \
      "vault" "HashiCorp Vault (OIDC, dynamic creds)" \
      "sops"  "Mozilla SOPS + age (encrypted in git)" \
      "env"   "Local .env file (not recommended)" 3>&1 1>&2 2>&3)

  MODULE_CHOICES=$(whiptail --title "$TITLE" --separate-output --checklist "Select modules to install" 20 70 10 \
      "hub" "Core web portal (required)" ON \
      "cybercore" "CyberCore orchestration (required)" ON \
      "cyberlabs" "Virtualization environment" OFF \
      "crucible" "CTF cyber range" OFF \
      "university" "Moodle LMS" OFF \
      "library" "Indexed resources" OFF \
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
# Backend secrets config (filled by you or automation)
# For Vault:
# VAULT_ADDR=
# VAULT_NAMESPACE=
# VAULT_TOKEN=
# For SOPS:
# SOPS_AGE_KEY_FILE=
ENV
  fi

  json_set '.first_run_done' 'true'
  echo "[Wizard] Config written to $CFG_FILE"
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
    echo "Debian 12 (bookworm) required. Detected: ${VERSION_CODENAME:-unknown}"
    exit 1
  fi

  require curl
  require gpg
  require yq

  local HOSTNAME IP IFACE CIDR GW
  HOSTNAME=$(yq -r '.pve.hostname' "$CFG_FILE")
  IP=$(yq -r '.pve.mgmt_cidr' "$CFG_FILE" | cut -d'/' -f1)

  if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "$IP $HOSTNAME ${HOSTNAME%%.*}" >> /etc/hosts
  fi
  hostnamectl set-hostname "$HOSTNAME"

  echo "[Proxmox] Adding APT repository..."
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list
  curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
    -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

  echo "[Proxmox] Installing packages..."
  apt-get update
  apt-get install -y pve-kernel-6.8 proxmox-ve postfix open-iscsi

  echo "[Proxmox] Configuring management network..."
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
  echo "[Proxmox] Base install complete. A reboot is required to switch to the Proxmox kernel."
}

# =========================
#   Post-Proxmox tweaks
# =========================
proxmox_postinstall_tweaks() {
  # Remove enterprise repo line if present to avoid nag (safe if absent)
  sed -i 's|^deb https://enterprise.proxmox.com/.*|# &|' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true

  # Enable nested virtualization
  echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-intel.conf || true
  echo "options kvm_amd nested=1"   > /etc/modprobe.d/kvm-amd.conf || true
  update-initramfs -u || true
  modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true

  echo "[Proxmox] Post-install tweaks completed."
}

# =========================
#   Secrets backend loader
# =========================
fetch_secrets() {
  local BACKEND
  BACKEND=$(yq -r '.secrets_backend' "$CFG_FILE")
  case "$BACKEND" in
    vault) require vault; require jq; source "$SECRETS_FILE" ;;
    sops)  require sops; require age; source "$SECRETS_FILE" ;;
    env)   source "$SECRETS_FILE" ;;
    *)     echo "Unknown secrets backend: $BACKEND"; exit 1 ;;
  esac
}

# =========================
#   Terraform/Ansible/Compose runners
# =========================
terraform_run() {
  local dir="$1"
  require terraform
  require yq
  pushd "$dir" >/dev/null
  terraform init -upgrade
  local env domain
  env=$(yq -r '.env' "$CFG_FILE")
  domain=$(yq -r '.domain' "$CFG_FILE")

  if [[ "$PLAN_MODE" == "true" ]]; then
    terraform plan -var "env=$env" -var "domain=$domain"
  else
    terraform apply -auto-approve -var "env=$env" -var "domain=$domain"
  fi
  popd >/dev/null
}

ansible_run() {
  local inventory="$1" playbook="$2"
  require ansible-playbook
  require yq
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
  require docker
  if [[ "$PLAN_MODE" == "true" ]]; then
    echo "[PLAN] Would run: docker compose --env-file .env.runtime up -d (in $dir)"
    return
  fi
  pushd "$dir" >/dev/null
  # Ensure an env file exists so compose doesn't error; feel free to populate earlier.
  [[ -f .env.runtime ]] || touch .env.runtime && chmod 600 .env.runtime
  docker compose --env-file .env.runtime up -d
  popd >/dev/null
}

# =========================
#   CyberCore + Hub
# =========================
install_cybercore_and_hub() {
  terraform_run terraform/core
  ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" site_core.yml
  compose_run compose/hub
  json_set '.core.installed' 'true'
}

# =========================
#   Modules
# =========================
install_modules() {
  local list
  list="$(yq -r '.modules | join(",")' "$CFG_FILE")"
  IFS=',' read -ra MODS <<< "$list"
  for m in "${MODS[@]}"; do
    case "$m" in
      hub|cybercore) ;; # already installed in core step

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

      university)
        terraform_run terraform/university
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" university.yml
        compose_run compose/university
        ;;

      library)
        terraform_run terraform/library
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" library.yml
        compose_run compose/library
        ;;

      wiki)
        terraform_run terraform/wiki
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" wiki.yml
        compose_run compose/wiki
        ;;

      archive)
        terraform_run terraform/archive
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" archive.yml
        compose_run compose/archive
        ;;

      forge)
        terraform_run terraform/forge
        ansible_run "inventories/$(yq -r '.env' "$CFG_FILE")" forge.yml
        compose_run compose/forge
        ;;

      "" ) ;; # ignore empty
      * )
        echo "[WARN] Unknown module '$m' — skipping."
        ;;
    esac
  done
  json_set '.modules.installed' 'true'
}

# =========================
#   Main
# =========================
if [[ "$RESUME_MODE" != "true" && "$(json_get '.first_run_done')" != "true" ]]; then
  first_run_wizard
fi

# Phase 1: Proxmox base install
if [[ "$(json_get '.pve.installed')" != "true" ]]; then
  install_proxmox_on_debian
  echo
  echo "==> Reboot now to load the Proxmox kernel, then run:"
  echo "    $0 --resume${PLAN_MODE:+ --plan}"
  echo
  exit 0
fi

# Phase 1b: Post-reboot Proxmox tweaks
proxmox_postinstall_tweaks

# Phase 2: Secrets (Vault/SOPS/env)
fetch_secrets

# Phase 3: CyberCore + Hub
if [[ "$(json_get '.core.installed')" != "true" ]]; then
  install_cybercore_and_hub
fi

# Phase 4: Selected modules
if [[ "$(json_get '.modules.installed')" != "true" ]]; then
  install_modules
fi

echo "✅ CyberHub install complete (plan mode: $PLAN_MODE)"