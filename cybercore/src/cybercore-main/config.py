import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from cybercore/.env
env_path = Path(__file__).parent.parent.parent / '.env'
load_dotenv(env_path)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'cybercore-postgres'),
    'port': int(os.getenv('DB_HOST_PORT', '5433')),
    'database': os.getenv('DB_NAME', 'cyberhub_core'),
    'user': os.getenv('DB_USER', 'cyberhub'),
    'password': os.getenv('DB_PASS', 'cyberpass')
}

# N8N configuration
N8N_CONFIG = {
    'host': os.getenv('N8N_HOST', 'n8n.localhost'),
    'port': int(os.getenv('N8N_PORT', '5678')),
    'protocol': 'http',
    'base_url': f"http://{os.getenv('N8N_HOST', 'n8n.localhost')}:8080"
}

# Ansible configuration
ANSIBLE_CONFIG = {
    'playbooks_dir': Path(__file__).parent.parent.parent / 'automation' / 'playbooks',
    'scripts_dir': Path(__file__).parent.parent.parent / 'automation' / 'scripts',
    'inventory': Path(__file__).parent.parent.parent / 'automation' / 'inventory'
}