# CyberLabs

The CyberLabs will be a cloud-like virtualization environment for use by students and faculty in order to ensure computation-heavy projects are supported without the need to deal with the  "red tape" often involved in large projects. This environment will be available to all university students and faculty upon request for a set amount of time and resources necessary to complete their proposed project. These environments will be based on a per-project Debian GNOME desktop environment utilizing KVM/QEMU and Cockpit facilitate virtualization. These desktop environments and their traffic will be closely monitored to ensure users are following the Terms of Service agreed upon following their request approval.

## Nested CyberLabs Cluster

- Node Names: cyberlab-node-#
- Use:
    - Student & faculty VMs
    - Student & faculty research projects
    - Automated, distributed fuzzing campaigns

## User Management

- Active Directory from the CyberHub domain.
- Custom method to provision, deploy, and configure per-project-based virtualization environments with specific hardware allotments (via Terraform, Ansible, and Bash scripts).

## How it Works

Upon the acceptance of a Resource Request, the required resources and users/group will be input into a script that will do the following:

1. Terraform

## How to Get Access

1. Request resources using Resource Request template
2. Send Resource Request to responsbile parties
3. Resource Request is reviewed and accepted (or returned for modification)
4. User(s) is/are created
5. Resources are alloted to user(s)
6. Resource Request is returned with acceptance, VPN config file(s), and initial user login instructions

## Resource Request Document

The necessary information needed is:

1. Project synopsis (what you're doing, why you're doing it)
2. Project type (personal, professional, school, etc.)
3. Resources needed (optional: Why? Including a "why" might increase chance of approval)
4. Project duration
5. Contact information