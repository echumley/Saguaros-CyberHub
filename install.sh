#!/usr/bin/env bash
set -euo pipefail

# ===== Config / state paths =====
STATE_DIR="/var/lib/cyberhub-installer"
STATE_FILE="${STATE_DIR}/state.json"
CFG_FILE="/etc/cyberhub/installer.yaml"       # non-secret runtime config
SECRETS_FILE="/etc/cyberhub/secrets.env"      # gitignored, chmod 600
LOG_FILE="/var/log/cyberhub-installer.log"

mkdir -p "$(dirname "$CFG_FILE")" "$STATE_DIR"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# ===== Helpers =====
require() { command -v "$1" >/dev/null || { echo "Need $1"; exit 1; }; }
json_get() { jq -r "$1" "$STATE_FILE" 2>/dev/null || echo ""; }
json_set() {
  local key="$1" value="$2"
  if [[ ! -s "$STATE_FILE" ]]; then echo '{}' > "$STATE_FILE"; fi
  tmp=$(mktemp); jq --arg v "$value" "$key = \$v" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

first_run_wizard() {
  require whiptail || { echo "Install 'whiptail' (newt)"; exit 1; }
  TITLE="CyberHub Installer"

  ENV=$(whiptail --title "$TITLE" --nocancel --menu "Select environment" 15 60 4 \
      "dev" "Development" \
      "stage" "Staging" \
      "prod" "Production" 3>&1 1>&2 2>&3)

  DOMAIN=$(whiptail --title "$TITLE" --nocancel --inputbox "Base domain (e.g. cyberhub.local or example.edu)" 10 60 "" 3>&1 1>&2 2>&3)

  PVE_HOSTNAME=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox hostname (FQDN recommended)" 10 60 "pve.${DOMAIN}" 3>&1 1>&2 2>&3)
  MGMT_IFACE=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt interface (e.g. eno1)" 10 60 "eno1" 3>&1 1>&2 2>&3)
  MGMT_CIDR=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox mgmt CIDR (e.g. 10.0.0.10/24)" 10 60 "" 3>&1 1>&2 2>&3)
  MGMT_GW=$(whiptail --title "$TITLE" --nocancel --inputbox "Proxmox default gateway (e.g. 10.0.0.1)" 10 60 "" 3>&1 1>&2 2>&3)

  BACKEND=$(whiptail --title "$TITLE" --nocancel --menu "Secrets backend" 15 60 3 \
      "vault" "HashiCorp Vault (OIDC, dynamic creds)" \
      "sops"  "Mozilla SOPS + age in git" \
      "env"   "Local .env (not recommended)" 3>&1 1>&2 2>&3)

  # module selection
  MODULE_CHOICES=$(whiptail --title "$TITLE" --separate-output --checklist "Select modules to install" 20 70 10 \
      "hub" "Core web portal (required)" ON \
      "cybercore" "CyberCore (orchestration brain, required)" ON \
      "cyberlabs" "Virtualization environment" OFF \
      "crucible" "CTF cyber range" OFF \
      "university" "Moodle LMS" OFF \
      "library" "Indexed resources" OFF \
      "wiki" "Cyber Wiki" OFF \
      "archive" "Malware/data archive" OFF \
      "forge" "Malware dev sandbox" OFF 3>&1 1>&2 2>&3) || true
  MODULES=$(echo "$MODULE_CHOICES" | tr '\n' ',' | sed 's/,$//')

  # write config file (non-secret)
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

  # secrets stub (gitignored, chmod 600)
  if [[ ! -f "$SECRETS_FILE" ]]; then
    touch "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
    cat >> "$SECRETS_FILE" <<ENV
# Filled by backend later
# VAULT_ADDR=
# VAULT_NAMESPACE=
# VAULT_TOKEN=             # if not using OIDC login flow
# SOPS_AGE_KEY_FILE=
ENV
  fi

  json_set '.first_run_done' 'true'
}

install_proxmox_on_debian() {
  # Idempotent check
  if dpkg -s pve-manager >/dev/null 2>&1; then
    echo "[Proxmox] Already installed."
    json_set '.pve.installed' 'true'
    return
  fi

  # Basic sanity
  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
    echo "Debian 12 (bookworm) required."
    exit 1
  fi

  # hosts entry
  yq -r '.pve.hostname' "$CFG_FILE" >/dev/null # ensures yq exists later
  require curl; require gpg; require yq
  HOSTNAME=$(yq -r '.pve.hostname' "$CFG_FILE")
  if ! grep -q "$HOSTNAME" /etc/hosts; then
    IP="${MGMT_CIDR%/*}"
    echo "$IP $HOSTNAME ${HOSTNAME%%.*}" >> /etc/hosts
  fi
  hostnamectl set-hostname "$HOSTNAME"

  echo "[Proxmox] Adding repositories..."
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list
  curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
    -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

  apt-get update
  # Install the Proxmox kernel + stack
  apt-get install -y pve-kernel-6.8 proxmox-ve postfix open-iscsi

  # Optional: configure network (basic mgmt iface)
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
  echo "[Proxmox] Install complete. Reboot required."
}

post_reboot_resume_unit() {
  # Create a oneshot systemd service to resume after reboot
  cat >/etc/systemd/system/cyberhub-installer-resume.service <<UNIT
[Unit]
Description=Resume CyberHub Installer after Proxmox reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cyberhub-installer-resume.sh

[Install]
WantedBy=multi-user.target
UNIT

  cat >/usr/local/sbin/cyberhub-installer-resume.sh <<'RESUME'
#!/usr/bin/env bash
set -euo pipefail
# Continue installer; assumes install.sh is in /root/cyberhub or similar
INSTALLER="${INSTALLER:-/root/cyberhub/install.sh}"
ENV=${ENV:-}
MODULES=${MODULES:-}
bash "$INSTALLER" --resume
RESUME
  chmod +x /usr/local/sbin/cyberhub-installer-resume.sh
  systemctl enable cyberhub-installer-resume.service
}

proxmox_postinstall_tweaks() {
  # Remove subscription nag, enable nested virt, load modules, etc.
  # (safe idempotent ops)
  sed -i 's/https:\/\/enterprise.proxmox.com\/debian\/pve/# &/' /etc/apt/sources.list.d/pve-enterprise.list || true
  echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-intel.conf || true
  echo "options kvm_amd nested=1"   > /etc/modprobe.d/kvm-amd.conf || true
  update-initramfs -u || true
  modprobe kvm_intel || modprobe kvm_amd || true
}

fetch_secrets() {
  BACKEND=$(yq -r '.secrets_backend' "$CFG_FILE")
  case "$BACKEND" in
    vault)
      require vault; require jq
      # Example: export a token or do OIDC login once
      source "$SECRETS_FILE" || true
      export VAULT_ADDR VAULT_NAMESPACE VAULT_TOKEN
      ;;
    sops)
      require sops; require age
      source "$SECRETS_FILE" || true
      export SOPS_AGE_KEY_FILE
      ;;
    env)
      source "$SECRETS_FILE" || true
      ;;
  esac
}

install_cybercore_and_hub() {
  # Terraform: create PVE resources, networks, storage; Ansible: configure host; docker: deploy hub/core
  pushd terraform/core >/dev/null
  terraform init -upgrade
  terraform apply -auto-approve \
    -var "env=$(yq -r '.env' "$CFG_FILE")" \
    -var "domain=$(yq -r '.domain' "$CFG_FILE")"
  popd >/dev/null

  pushd ansible >/dev/null
  ansible-playbook -i inventories/$(yq -r '.env' "$CFG_FILE") site_core.yml \
    -e "@${CFG_FILE}"
  popd >/dev/null

  pushd compose/hub >/dev/null
  # Generate ephemeral env file for compose
  RUNTIME_ENV="$(pwd)/.env.runtime"
  : > "$RUNTIME_ENV"
  chmod 600 "$RUNTIME_ENV"
  # Example vars (fill via vault/sops lookups in a real impl)
  echo "CYBERHUB_DOMAIN=$(yq -r '.domain' "$CFG_FILE")" >> "$RUNTIME_ENV"
  docker compose --env-file "$RUNTIME_ENV" up -d
  popd >/dev/null

  json_set '.core.installed' 'true'
}

install_modules() {
  IFS=',' read -ra MODS <<< "$(yq -r '.modules | join(",")' "$CFG_FILE")"
  for m in "${MODS[@]}"; do
    case "$m" in
      cyberlabs)
        pushd terraform/cyberlabs >/dev/null
        terraform init -upgrade
        terraform apply -auto-approve -var-file="../../tfvars/$(yq -r '.env' "$CFG_FILE").tfvars.json"
        popd >/dev/null
        ansible-playbook -i ansible/inventories/$(yq -r '.env' "$CFG_FILE") ansible/cyberlabs.yml \
          -e "@${CFG_FILE}"
        pushd compose/cyberlabs >/dev/null
        docker compose --env-file ../../secrets/.env.runtime up -d || true
        popd >/dev/null
        ;;
      crucible)
        # repeat pattern per module…
        ;;
      university|library|wiki|archive|forge)
        ;;
      hub|cybercore)
        ;; # already done in core
    esac
  done
  json_set '.modules.installed' 'true'
}

usage() {
  cat <<USAGE
Usage: $0 [--resume]
- Runs a first-run wizard, installs Proxmox on Debian, reboots, resumes, then installs CyberCore/Hub and selected modules.
USAGE
}

# ===== Main =====
if [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi

if [[ "${1:-}" != "--resume" && "$(json_get '.first_run_done')" != "true" ]]; then
  require jq; require yq
  first_run_wizard
fi

if [[ "$(json_get '.pve.installed')" != "true" ]]; then
  install_proxmox_on_debian
  post_reboot_resume_unit
  echo "Rebooting now to switch to Proxmox kernel..."
  sleep 2
  systemctl reboot
  exit 0
fi

# We are post-reboot at this point
proxmox_postinstall_tweaks
fetch_secrets

if [[ "$(json_get '.core.installed')" != "true" ]]; then
  install_cybercore_and_hub
fi

if [[ "$(json_get '.modules.installed')" != "true" ]]; then
  install_modules
fi

echo "✅ All done. CyberHub installed."