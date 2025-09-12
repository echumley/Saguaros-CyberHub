# The Saguaros CyberHub Project

The official repo of the UA Cyber Saguaros CyberHub project.

## Project Description

The Saguaros CyberHub is the official cybersecurity lab, cyber warfare range, and eLearning platform of the Cyber Saguaros, the University of Arizona's largest cybersecurity club. The CyberHub's purpose is split into three main goals that guide our effort throughout this project:

1. Provide club members with the opportunity to supplement their undergraduate and graduate-level coursework with hands-on offensive and defensive security training.
2. Create a training model & environment for club Capture the Flag (CTF) teams.
3. Stay free for club members.

## Project Ethos

Our goal is to follow this set of ethos set by the team:

1. **Open Source First**: Prioritize free, open-source software to ensure accessibility and transparency. All core components are built on community-supported technologies.
2. **Infrastructure as Code**: Maintain complete portability through IAC practices, automated deployment scripts, and containerization. The entire environment can be reproduced on any compatible hardware platform.
3. **Student Accessibility**: Keep deployments free for all students while ensuring enterprise-grade security and performance standards.
4. **Continuous Learning**: Provide hands-on experience with real-world tools and scenarios that mirror professional cybersecurity environments.
5. **Community Driven**: Foster collaboration between students, faculty, and industry professionals to create a comprehensive learning ecosystem.
6. **Security by Design**: Implement defense-in-depth strategies and zero-trust principles throughout the infrastructure to create a secure learning environment.

## Project Modules

Here are the main modules that will make up the CyberHub:

1. **CyberCore** - Central management system handling authentication, automation, and orchestration across all modules.
2. **The Hub** - The website/landing page where users authorize and get access to the other sections of the CyberHub.
3. **CyberLabs** - Virtualization environment for student and faculty projects.
4. **The Crucible** - A fully featured, CTF-style cyber warfare range with vulnerable hosts, networking devices, and enterprise environments.
5. **Saguaros University** - Moodle eLearning platform (LMS) with courses and digital badges.
6. **The Library** - An organized, properly indexed repository of eBooks, PDF guides, research articles, and cybersecurity resources.
7. **Saguaros Wiki** - A wiki with vulnerable machine walkthroughs, red/blue team skill playbooks, cheat sheets, and the CyberHub project documentation.
8. **The Archive** - A deep archive of malware samples, projects, scrapped data samples, etc.
9. **The Forge** - An isolated environment where users can deploy, develop, and reverse engineer malicious software for educational purposes.

## Live Preview

🚧 In progress! Demo environments will be hosted internally during alpha testing. Public preview pending.

## Project Diagram

![alt text](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub-Architecture.png?raw=true)

## Project Roadmap

### Stage 1

#### Goal: CyberHub Infrastructure Deployment

- [x] Network deployment
- [x] Hardware deployment
- [x] Authentication & domain controller deployment (Keycloak, FreeIPA, SSSD configured)
- [x] Internal service template creation (VMs, Docker, K3s, etc.)
- [x] Module nested virtualization template creation
- [x] SIEM/SOAR deployment (Log ingestion stack, monitoring services)
- [x] Deploy necessary other internal services (Vault, automation frameworks)

### Stage 2

#### Goal: Crucible Proof of Concept

- [ ] Authentication stack deployment
- [ ] Primary application deployment (ctfd or custom framework)
- [ ] Crucible internal system
- [ ] Documentation upload and refinement
- [ ] Proof of concept demonstration

### Stage 3

#### Goal: Alpha Launch & Private Deployment

- [ ] Further development of CyberHub internal system
- [ ] Secondary module deployments
- [ ] Vulnerable machine development
- [ ] Pre-alpha testing & function verification
- [ ] Alpha testing, feedback, and monitoring strategy development
- [ ] Documentation refinement
- [ ] Alpha launch & private deployment to UA Cyber Saguaros

### Stage 4

#### Goal: Beta Launch & Further Testing

- [ ] Post-alpha refinement (bug-fixes, stabilization, etc.)
- [ ] Performance optimization
- [ ] UI improvement
- [ ] Security & compliance refinement
- [ ] Beta testing, feedback, and monitoring strategy development
- [ ] Documentation refinement
- [ ] Beta launch & public deployment supported

### Stage 5

#### Goal: Release & Live Preview

- [ ] Publish first release
- [ ] Deploy live preview
- [ ] Continue improvements and bug fixes

## Network Traffic Diagram

![alt text](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub%20Traffick%20v1.2.png?raw=true)
*Infrastructure subject to change*

## Network Architecture

![Saguaros CyberLab Network](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/SaguarosCyberLab-Network-v1.0.png?raw=true)

## Virtualization Infrastructure

![CyberHub Virtualization](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/images/CyberHub-Virtualization.png?raw=true)

## Infrastructure & Automation

The CyberHub infrastructure is managed through Infrastructure as Code (IaC) principles:

- **Ansible Automation**: Comprehensive playbooks for service deployment and configuration
- **Docker Orchestration**: Containerized services using Docker Compose for portability
- **Proxmox Templates**: Automated VM provisioning for various Linux distributions
- **Internal Services**: Monitoring, logging, SIEM/SOAR, and backup solutions
- **Secrets Management**: HashiCorp Vault integration for secure credential storage

## CyberHub Modules

### CyberCore

CyberCore serves as the central nervous system of the CyberHub, providing:

- **Authentication Services**: Integration with Keycloak, FreeIPA, LDAP, and Samba for unified authentication
- **Automation Framework**: Ansible playbooks and inventory management for infrastructure deployment
- **Front-end Management**: The Hub interface for user access and module navigation
- **Service Orchestration**: Docker Compose configurations for containerized service deployment
- **API Integration**: RESTful APIs for inter-module communication

### CyberLabs

The CyberLabs will be a cloud-like virtualization environment for use by students and faculty in order to ensure computation-heavy projects are supported without the need to deal with the  "red tape" often involved in large projects. This environment will be available to all university students and faculty upon request for a set amount of time and resources necessary to complete their proposed project. These environments will be based on a per-project Debian GNOME desktop environment utilizing KVM/QEMU and Cockpit facilitate virtualization. These desktop environments and their traffic will be closely monitored to ensure users are following the Terms of Service agreed upon following their request approval.

### The Crucible

#### Range Types

Below is a general list of planned range types or "lanes." These are isolated networks in which one player or team will connect to access their target machines(s).

1. Single player vs. single target
2. Single player vs. multiple targets/network
3. Multiple players vs. single target (King of the Hill)
4. Team vs. single target
5. Team vs. multiple targets/network
6. Team vs. team (Attack-Defend)
7. Live SOC incident response

#### Extra Services

These services will be openly available for use by registered players (internally or externally) to assist in CTF competitions.

1. Web-based RDP Kali machine (for those who can't run it locally)
2. SIEM/SOAR stack (inspired by WRCCDC)
3. Hashcat server (GPU server running Hashtopolis)

---

### Saguaros University

#### Learning Courses

1. CTF fundamentals
2. Networking fundamentals
3. IT concept fundamentals
4. Red team fundamentals
5. Blue team fundamentals
6. King of the hill fundamentals
7. Tool spotlights
8. Malware development