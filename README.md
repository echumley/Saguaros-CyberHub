# The Saguaros CyberHub Project

The official repo of the UA Cyber Saguaros CyberHub project.

## Project Description

The Saguaros CyberHub is the official cybersecurity lab, cyber warfare range, and eLearning platform of the Cyber Saguaros, the University of Arizona's largest cybersecurity club. The CyberHub's purpose is split into three main goals that guide our effort throughout this project:

1. Provide club members with the opportunity to supplement their undergraduate and graduate-level coursework with hands-on offensive and defensive security training.
2. Create a training model & environment for club Capture the Flag (CTF) teams.
3. Stay free for club members.

## Project Ethos

Our goal is to follow this set of ethos set by the team:

1. Use free, open-source software wherever possible.
2. Keep the project components portable for use on any hardware platform by utilizing IAC, frameworks, and scripts.
3. Keep any deployment of the project free for students.

## Project Modules

Here are the main modules that will make up the CyberHub:

1. The Hub - The website/landing page where users authorize and get access to the other sections of the CyberHub.
2. CyberLabs - Virtualization environment for student and faculty projects.
3. The Crucible - A fully featured, CTF-style cyber warfare range with vulnerable hosts, networking devices, and enterprise environments.
4. Saguaros University - Moodle eLearning platform (LMS) with courses and digital badges.
5. Library - An organized, properly indexed repository of eBooks, PDF guides, research articles, and cybersecurity resources.
6. Cyber Wiki - A wiki with vulnerable machine walkthroughs, red/blue team skill playbooks, cheat sheets, and the CyberHub project documentation.
7. The Archive - A deep archive of malware samples, projects, scrapped data samples, etc.
8. The Forge - An isolated environment where users can deploy, develop, and reverse engineer malicious software for educational purposes.

## Live Preview

🚧 In progress! Demo environments will be hosted internally during alpha testing. Public preview pending.

## Project Diagram

![alt text](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/CyberHub-Architecture.png?raw=true)

## Project Roadmap

### Stage 1

#### Goal: CyberHub Infrastructure Deployment

- [x] Network deployment
- [x] Hardware deployment
- [ ] Authentication & domain controller deployment
- [x] Internal service template creation (VMs, Docker, K3s, etc.)
- [ ] Module nested virtualization template creation
- [ ] SIEM/SOAR deployment
- [ ] Deploy necessary other internal services

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

![alt text](https://github.com/echumley/Saguaros-CyberHub/blob/main/resources/CyberHub%20Traffick%20v1.1.png?raw=true)
*Infrastructure subject to change*

## CyberHub Modules

### CyberLabs

The CyberLabs will be a cloud-like virtualization environment for use by students and faculty in order to ensure computation-heavy projects are supported without the need to deal with the  "red tape" often involved in large projects. This environment will be available to all university students and faculty upon request for a set amount of time and resources necessary to complete their proposed project. These environments will be based on a per-project Debian GNOME desktop environment utilizing KVM/QEMU and Cockpit facilitate virtualization. These desktop environments and their traffic will be closely monitored to ensure users are following the Terms of Service agreed upon following their request approval.

---

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
3. Red team fundamentals
4. Blue team fundamentals
5. King of the hill fundamentals
6. Tool spotlights
