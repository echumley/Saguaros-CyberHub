import requests
import subprocess
import json
import logging
from typing import Dict, List, Optional, Any
from urllib.parse import urljoin

logger = logging.getLogger(__name__)


class N8nClient:
    def __init__(self, config: dict):
        self.base_url = config.get('base_url', 'http://n8n.localhost:8080')
        self.host = config.get('host', 'n8n.localhost')
        self.port = config.get('port', 5678)
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Optional[Dict]:
        """Make HTTP request to n8n API"""
        url = urljoin(self.base_url, endpoint)
        try:
            response = self.session.request(method, url, **kwargs)
            response.raise_for_status()
            return response.json() if response.content else None
        except requests.exceptions.RequestException as e:
            logger.error(f"N8n API request failed: {e}")
            return None
    
    def trigger_workflow(self, workflow_id: str, data: Optional[Dict] = None) -> Dict[str, Any]:
        """Trigger a workflow by ID via webhook"""
        # N8n webhook URL format
        webhook_url = f"{self.base_url}/webhook/{workflow_id}"
        
        try:
            response = self.session.post(webhook_url, json=data or {})
            response.raise_for_status()
            
            result = {
                'success': True,
                'workflow_id': workflow_id,
                'status_code': response.status_code,
                'response': response.json() if response.content else None
            }
            logger.info(f"Triggered workflow {workflow_id}")
            return result
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to trigger workflow {workflow_id}: {e}")
            return {
                'success': False,
                'workflow_id': workflow_id,
                'error': str(e)
            }
    
    def list_workflows(self) -> List[Dict[str, Any]]:
        """List all workflows (requires n8n API access)"""
        # This would require n8n API authentication
        # For now, return a placeholder
        logger.warning("Workflow listing requires n8n API authentication setup")
        return [
            {
                'id': 'example-1',
                'name': 'Example Workflow 1',
                'active': True,
                'webhook_id': 'webhook-1'
            },
            {
                'id': 'example-2', 
                'name': 'Example Workflow 2',
                'active': False,
                'webhook_id': 'webhook-2'
            }
        ]
    
    def get_workflow_executions(self, workflow_id: str) -> List[Dict[str, Any]]:
        """Get execution history for a workflow"""
        # This would require n8n API authentication
        logger.warning("Execution history requires n8n API authentication setup")
        return []


class N8nCLI:
    """Direct n8n CLI access via Docker"""
    
    def __init__(self, container_name: str = "cybercore-n8n-1"):
        self.container_name = container_name
    
    def _run_command(self, command: List[str]) -> Dict[str, Any]:
        """Run n8n CLI command in Docker container"""
        docker_cmd = ["docker", "exec", self.container_name, "n8n"] + command
        
        try:
            result = subprocess.run(
                docker_cmd,
                capture_output=True,
                text=True,
                check=True
            )
            
            return {
                'success': True,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'command': ' '.join(command)
            }
            
        except subprocess.CalledProcessError as e:
            logger.error(f"N8n CLI command failed: {e}")
            return {
                'success': False,
                'stdout': e.stdout,
                'stderr': e.stderr,
                'command': ' '.join(command),
                'error': str(e)
            }
    
    def export_workflow(self, workflow_id: str, output_file: Optional[str] = None) -> Dict[str, Any]:
        """Export a workflow to JSON"""
        cmd = ["export", "workflow", "--id", workflow_id]
        if output_file:
            cmd.extend(["--output", output_file])
        
        return self._run_command(cmd)
    
    def import_workflow(self, input_file: str) -> Dict[str, Any]:
        """Import a workflow from JSON"""
        cmd = ["import", "workflow", "--input", input_file]
        return self._run_command(cmd)
    
    def list_workflows(self) -> Dict[str, Any]:
        """List all workflows via CLI"""
        cmd = ["list", "workflow"]
        result = self._run_command(cmd)
        
        if result['success'] and result['stdout']:
            try:
                # Parse the output if it's JSON
                workflows = json.loads(result['stdout'])
                result['workflows'] = workflows
            except json.JSONDecodeError:
                # Output might be in a different format
                result['workflows'] = []
        
        return result
    
    def execute_workflow(self, workflow_id: str, data: Optional[Dict] = None) -> Dict[str, Any]:
        """Execute a workflow via CLI"""
        cmd = ["execute", "--id", workflow_id]
        
        if data:
            # Pass data as JSON string
            cmd.extend(["--input", json.dumps(data)])
        
        return self._run_command(cmd)
    
    def get_status(self) -> Dict[str, Any]:
        """Get n8n status"""
        cmd = ["status"]
        return self._run_command(cmd)