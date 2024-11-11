# CyberHub Infrastrure
This is the folder containing all the infrastructure-related scripts, Ansible playbooks, Docker Compose files, etc.

## Network Layout
This is a general layout of the network.

### VLANs
10.1.10.0/24 on VLAN 10: Management Network - Remote server management, admin web UIs, switches, etc.
10.1.20.0/24 on VLAN 20: Internal Services Network - Homepage, SEIM, authentication stack, etc.
10.1.30.0/24 on VLAN 30: Trusted Network - Admin VPN access & only subnet with routes to all major services.
10.1.40.0/24 on VLAN 40: WiFi Network - WiFi network in the case of local CTF events.
10.1.50.0/24 on VLAN 50: Lab Network - Used for testing of new servies/infrastructure.
10.1.60.0/24 on VLAN 60: DMZ Network - All externally-facing services, reverse proxies, CTFd, player OpenVPN, etc.
10.1.70-254.0/24 on VLAN 70-254: Range Networks - Used for range lanes, vulnerable VMs, etc.

## IPs
* Note: The last octet of the IP is the same as the Proxmox VM ID number in order to quickly reference them when looking at the dashboard.
    - Proxmox Templates: 10.1.10.100-109
    - Authentication Services: 10.1.110-119
    - Internal Services: 10.1.20.120-129
    - External Access & Extra Services: 10.1.60.160-169
    - Range: 10.1.70.170-179

## Template Organization
* Keep template organization by numbering based on the VLAN
    - Base image templates: 1000-1099
    - Management templates: 1100-1199
    - Internal service templates: 1200-1299
    - Trusted service templates: 1300-1399
    - WiFi service templates: 1400-1499
    - Lab service templates: 1500-1599
    - DMZ service templates: 1600-1699
    - Range templates: 1700-9999

## SSH Keys
* Utilize seperate keys for each service, but during the inital deployment we're utilizing three sets of SSH key pairs:
    - saguaros-admin-key
    - saguaros-ansible-key
    - range-ansible-key