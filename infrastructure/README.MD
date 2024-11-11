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
