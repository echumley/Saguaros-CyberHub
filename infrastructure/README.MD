# CyberHub Infrastrure

This is the folder containing all the infrastructure-related scripts, Ansible playbooks, Docker Compose files, etc.

## Network Layout

This is a general layout of the network.

### VLANs

10.1.10.0/24 on VLAN 10: Management Network - Remote server management, admin web UIs, switches, etc. \
10.1.20.0/24 on VLAN 20: Internal Services Network - Homepage, SEIM, authentication stack, etc. \
10.1.30.0/24 on VLAN 30: Trusted Network - Admin VPN access & only subnet with routes to all major services. \
10.1.40.0/24 on VLAN 40: WiFi Network - WiFi network in the case of local CTF events. \
10.1.50.0/24 on VLAN 50: DMZ Network - All externally-facing services, reverse proxies, CTFd, player OpenVPN, etc. \
10.1.60.0/24 - 10.1.99.0/24 on VLAN 60-99: Lab Networks - Used for testing of new services/infrastructure, student projects, malware labs, etc. \
10.1.100.0-  10.1.254.0/24 on VLAN 100-254: Range Networks - Used for range lanes, vulnerable VMs, etc.

### IP Spacing

#### 10.1.10.0/24: Management services

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-9: Networking devices (Switches, downstream routers, APs, etc.) \
x.x.x.10-19: Compute servers 1 (Hypervisors & networking ports) \
x.x.x.20-29: Compute servers 2 \
x.x.x.30-39: Compute servers 3 \
x.x.x.40-49: Compute servers 4 \
x.x.x.50-59: Compute servers 5 \
x.x.x.60-69: Storage servers \
x.x.x.70-79: Remote server management 1 \
x.x.x.80-89: Remote server management 2 \
x.x.x.90-99: Remote server management 3 \

#### 10.1.20.0/24: Internal services

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-9: Logging services (Loki, Grafana, Prometheus, etc.) \
x.x.x.10-19: SIEM & SOAR services (Wazuh, Zeek, TheHive, etc.) \
x.x.x.20-29: Authentication services (Active Directory) \
x.x.x.30-39: Backup services \
x.x.x.40-49: Network storage shares \
x.x.x.50-99: Others

#### 10.1.30.0/24: Trusted network & VPN access

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-99: Workstations/trusted devices \
x.x.x.100-254: Administrator VPN endpoints

#### 10.1.40.0/24: WiFi-connected devices

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-9: WAPs \
x.x.x.10-254: DHCP

#### 10.1.50.0/24: DMZ for externally facing services

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-9: External access (Traefik, Crowdsec, etc.) \
x.x.x.10-99: CyberHub services (ctfd, Moodle, etc.) \
x.x.x.100-254: DHCP

#### 10.1.60-10.1.99.0/24: Lab networks

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-254: DHCP

#### 10.1.100-254.0/24: The Crucible Range Lanes

x.x.x.1: VLAN/subnet gateway \
x.x.x.2-9: VPN endpoints (if necessary) \
x.x.x.10-254: DHCP

## Proxmox Organization

### VM IDs

The VM IDs to be set are combinations of the VLAN the VM is connected to and the VM's IPv4 address. The first number of the 3-digit number is the VLAN divided by 10, while the second and third numbers are the IP address's last octet which is to be kept below 3 digits.

Example: VM ID of 210 means that the VM lives on VLAN 20 and has an IPv4 address ending in .10.

### Template Organization

Keep template organization by numbering based on the VLAN
- Base image templates: 1000-1099
- Management templates: 1100-1199
- Internal service templates: 1200-1299
- Trusted service templates: 1300-1399
- WiFi service templates: 1400-1499
- DMZ service templates: 1500-1599
- Lab service templates: 1600-1999
- Range templates: 10000-99999

## SSH Keys

Utilize separate keys for each service, but during the initial deployment we're utilizing three sets of SSH key pairs:
- saguaros-admin-key
- saguaros-ansible-key
- range-ansible-key
