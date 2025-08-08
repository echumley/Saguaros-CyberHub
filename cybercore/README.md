# 🧠 CyberCore: The Central Brain of CyberHub

## 🔗 Responsibilities:
* User provisioning & identity mapping (via LDAP/Keycloak)
* Profile DB (badges, VMs, progress, achievements)
* Inter-module orchestration via webhooks or API calls
* Audit logs & activity tracking
* Triggering and monitoring workflows across modules via n8n

## Flowchart

flowchart TD
    A[User logs in via Keycloak]
    A --> B[Hub redirects to Dashboard UI]
    B --> C[Dashboard fetches profile data via FastAPI API]
    C --> D[FastAPI queries PostgreSQL]
    C --> E[FastAPI sends update to n8n via webhook or DB write]
    F[CyberLabs, Crucible, University] --> E