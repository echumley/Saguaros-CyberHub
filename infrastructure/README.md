# CyberHub Infrastrure

This is the folder containing all the infrastructure-related scripts, Ansible playbooks, Docker Compose files, etc.

## Virtualization

![alt text](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub-Virtualization-v1.0.png?raw=true)

## CyberHub Bare-Metal Cluster

The CyberHub bare-metal cluster will each host a set of nested virtualization environments to better segment the various sub-modules (ie. CyberLabs, The Forge, etc.) along with numerous services to ensure smooth and secure operation of the entire project. This may include non-open-source software as these modules can each be ran on their own (see standalone configurations in the modules' directories (planned - WIP)) and it eases adminstrative strain to maintain the physical CyberHub infrastructure.

### Internal Services

*NOTE: These services may live as VMs on the CyberHub bare-metal cluster or in the nested Docker Swarm cluster/K3s cluster.*

- Active Directory
- SIEM/SOAR (ideally Splunk Enterprise)
- Change management software
- Logging stack
- Network monitoring
- OS download/update caching
- Reverse proxy
- Keycloak
- NetBox Labs Enterprise
- Password manager
- Secrets manager

## Network Layout

This is a general layout of the network.

![Saguaros CyberLab Network](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberLabs-Network-v1.0.png?raw=true)

*NOTE: The CyberHub heavily utilizes netested virtualization and network segmentation via SDNs, VLANs, and VXLANs*

### Subnets

`100.100.0.0/16` - CyberCore & CyberHub infrastructure \
`100.101.0.0/16` - CyberLabs infrastructure \
`100.102.0.0/16` - Crucible infrastructure \
`100.103.0.0/16` - Forge infrastructure \
`100.104-149.0.0/16` - Unused \
`100.150-199.0.0/16` - Student project infrastructure \
`100.200-254.0.0/16` - Remote site infrastructure

### VLANs

`x.x.10.0/24` on `VLAN 10`: Management Network - Remote server management, admin web UIs, switches, etc. \
`x.x.20.0/24` on `VLAN 20`: Internal Services Network - Homepage, SEIM, authentication stack, etc. \
`x.x.30.0/24` on `VLAN 30`: Trusted Network - Admin VPN access & only subnet with routes to all major services. \
`x.x.40.0/24` on `VLAN 40`: WiFi Network - WiFi network in the case of local CTF events. \
`x.x.50.0/24` on `VLAN 50`: DMZ Network - All externally-facing services, reverse proxies, VPN endpoints, etc. \
`x.x.60.0/24` on `VLAN 60`: Lab Networks - Used for testing of new services/infrastructure, admin projects, etc. \
`x.x.70.0/24` on `VLAN 80`: Quarantine Network \
`x.x.99.0/24` on `VLAN 99`: Ceph Network (not routed)

### IP Spacing

#### 100.x.10.0/24: Management services

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.2-9`: Networking devices (Switches, downstream routers, APs, etc.) \
`x.x.x.10-19`: Compute servers 1 (Hypervisors & networking ports) \
`x.x.x.20-29`: Compute servers 2 \
`x.x.x.30-39`: Compute servers 3 \
`x.x.x.40-49`: Compute servers 4 \
`x.x.x.50-59`: Compute servers 5 \
`x.x.x.60-69`: Storage servers \
`x.x.x.70-79`: Remote server management 1 \
`x.x.x.80-89`: Remote server management 2 \
`x.x.x.90-99`: Remote server management 3 \
`x.x.x.100-254`: DHCP

#### 100.x.20.0/24: Internal services

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.2-9`: Logging services (Loki, Grafana, Prometheus, etc.) \
`x.x.x.10-19`: SIEM & SOAR services (Wazuh, Zeek, TheHive, etc.) \
`x.x.x.20-29`: Authentication services (LDAP, FreeIPA, Keycloack, etc.) \
`x.x.x.30-39`: Backup services \
`x.x.x.40-49`: Network storage shares \
`x.x.x.50-99`: Others \
`x.x.x.100-254`: DHCP

#### 100.x.30.0/24: Trusted network & VPN access

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.2-99`: Workstations/trusted devices \
`x.x.x.100-254`: Administrator VPN endpoints

#### 100.x.40.0/24: WiFi-connected devices

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.2-9`: WAPs \
`x.x.x.10-254`: DHCP

#### 10.x.50.0/24: DMZ for externally facing services

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.2-9`: External access (Traefik, Crowdsec, etc.) \
`x.x.x.10-99`: CyberHub services (ctfd, Moodle, etc.) \
`x.x.x.100-254`: DHCP

#### 100.x.60-10.x.99.0/24: Lab networks

`x.x.x.1`: VLAN/subnet gateway \
`x.x.x.100-254`: DHCP

## Architecture Overview

![CyberHub Architecture](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub-Architecture-v1.0.png?raw=true)

## Network Traffic Flow

![CyberHub Traffic Flow](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub%20Traffick%20v1.2.png?raw=true)

## Proxmox Organization

### VM IDs

The VM IDs to be set are combinations of the VLAN the VM is connected to and the VM's IPv4 address. The first number of the 3-digit number is the VLAN divided by 10, while the second and third numbers are the IP address's last octet which is to be kept below 3 digits.

Example: VM ID of 210 means that the VM lives on VLAN 20 and has an IPv4 address ending in .10.

### Template Organization

Keep template organization by numbering based on the VLAN

- Base image templates: `1000-1099`
- Management templates: `1100-1199`
- Internal service templates: `1200-1299`
- Trusted service templates: `1300-1399`
- WiFi service templates: `1400-1499`
- DMZ service templates: `1500-1599`
- Lab service templates: `1600-1999`
- Miscellaneous templates: `+2000`

## SSH Keys

Utilize separate keys for each service, but during the initial deployment we're utilizing three sets of SSH key pairs: \
NOTE: These keys are not publically available, and until we implement a better secret manager, just create these keys or modify the Ansible/Docker/Terraform config files.

- `saguaros-admin-key`
- `saguaros-ansible-key`
- `range-ansible-key`

## CyberLabs Nested Cluster

To be continued...