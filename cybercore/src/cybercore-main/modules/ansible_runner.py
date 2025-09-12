import subprocess
import os
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
import tempfile
import yaml

logger = logging.getLogger(__name__)


class AnsibleRunner:
    def __init__(self, config: dict):
        self.playbooks_dir = Path(config.get('playbooks_dir', './automation/playbooks'))
        self.scripts_dir = Path(config.get('scripts_dir', './automation/scripts'))
        self.inventory = config.get('inventory', './automation/inventory')
        
        # Ensure directories exist
        self.playbooks_dir.mkdir(parents=True, exist_ok=True)
        self.scripts_dir.mkdir(parents=True, exist_ok=True)
    
    def _run_command(self, command: List[str], cwd: Optional[str] = None,
                    env: Optional[Dict] = None) -> Dict[str, Any]:
        """Run a command and capture output"""
        # Merge environment variables
        cmd_env = os.environ.copy()
        if env:
            cmd_env.update(env)
        
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                cwd=cwd,
                env=cmd_env,
                check=False  # Don't raise on non-zero exit
            )
            
            return {
                'success': result.returncode == 0,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'return_code': result.returncode,
                'command': ' '.join(command)
            }
            
        except Exception as e:
            logger.error(f"Command execution failed: {e}")
            return {
                'success': False,
                'stdout': '',
                'stderr': str(e),
                'return_code': -1,
                'command': ' '.join(command),
                'error': str(e)
            }
    
    def list_playbooks(self) -> List[Dict[str, Any]]:
        """List available Ansible playbooks"""
        playbooks = []
        
        if self.playbooks_dir.exists():
            for file in self.playbooks_dir.glob('*.yml'):
                try:
                    with open(file, 'r') as f:
                        content = yaml.safe_load(f)
                        playbooks.append({
                            'name': file.stem,
                            'path': str(file),
                            'description': self._extract_playbook_description(content)
                        })
                except Exception as e:
                    logger.warning(f"Failed to parse playbook {file}: {e}")
                    playbooks.append({
                        'name': file.stem,
                        'path': str(file),
                        'description': 'Unable to parse playbook'
                    })
        
        return playbooks
    
    def _extract_playbook_description(self, content: Any) -> str:
        """Extract description from playbook content"""
        if isinstance(content, list) and content:
            first_play = content[0]
            if isinstance(first_play, dict):
                return first_play.get('name', 'No description')
        return 'No description'
    
    def run_playbook(self, playbook_name: str, extra_vars: Optional[Dict] = None,
                    tags: Optional[List[str]] = None, limit: Optional[str] = None,
                    check: bool = False, verbose: int = 0) -> Dict[str, Any]:
        """Run an Ansible playbook"""
        # Find playbook file
        playbook_path = None
        if Path(playbook_name).exists():
            playbook_path = playbook_name
        else:
            # Look in playbooks directory
            for ext in ['.yml', '.yaml']:
                path = self.playbooks_dir / f"{playbook_name}{ext}"
                if path.exists():
                    playbook_path = str(path)
                    break
        
        if not playbook_path:
            return {
                'success': False,
                'error': f"Playbook '{playbook_name}' not found"
            }
        
        # Build ansible-playbook command
        cmd = ["ansible-playbook", playbook_path]
        
        # Add inventory if exists
        if self.inventory and Path(self.inventory).exists():
            cmd.extend(["-i", str(self.inventory)])
        
        # Add extra variables
        if extra_vars:
            cmd.extend(["--extra-vars", json.dumps(extra_vars)])
        
        # Add tags
        if tags:
            cmd.extend(["--tags", ",".join(tags)])
        
        # Add limit
        if limit:
            cmd.extend(["--limit", limit])
        
        # Add check mode
        if check:
            cmd.append("--check")
        
        # Add verbosity
        if verbose > 0:
            cmd.append("-" + "v" * min(verbose, 4))
        
        logger.info(f"Running playbook: {playbook_name}")
        result = self._run_command(cmd, cwd=str(self.playbooks_dir.parent))
        
        # Parse output for summary
        if result['success']:
            result['summary'] = self._parse_ansible_summary(result['stdout'])
        
        return result
    
    def _parse_ansible_summary(self, output: str) -> Dict[str, Any]:
        """Parse Ansible output for execution summary"""
        summary = {
            'plays': 0,
            'tasks': 0,
            'changed': 0,
            'failures': 0,
            'skipped': 0,
            'rescued': 0
        }
        
        # Simple parsing - look for PLAY RECAP
        if 'PLAY RECAP' in output:
            recap_section = output.split('PLAY RECAP')[1]
            lines = recap_section.strip().split('\n')
            
            for line in lines:
                if ':' in line and 'ok=' in line:
                    # Parse host summary line
                    parts = line.split()
                    for part in parts:
                        if '=' in part:
                            key, value = part.split('=')
                            if key == 'changed':
                                summary['changed'] += int(value)
                            elif key == 'failed':
                                summary['failures'] += int(value)
                            elif key == 'skipped':
                                summary['skipped'] += int(value)
                            elif key == 'rescued':
                                summary['rescued'] += int(value)
        
        return summary
    
    def run_script(self, script_name: str, args: Optional[List[str]] = None,
                  env: Optional[Dict] = None) -> Dict[str, Any]:
        """Run a script from the scripts directory"""
        # Find script file
        script_path = None
        if Path(script_name).exists():
            script_path = Path(script_name)
        else:
            # Look in scripts directory
            script_path = self.scripts_dir / script_name
            if not script_path.exists():
                # Try with common extensions
                for ext in ['.sh', '.py', '.bash']:
                    path = self.scripts_dir / f"{script_name}{ext}"
                    if path.exists():
                        script_path = path
                        break
        
        if not script_path or not script_path.exists():
            return {
                'success': False,
                'error': f"Script '{script_name}' not found"
            }
        
        # Make script executable
        script_path.chmod(0o755)
        
        # Build command
        cmd = [str(script_path)]
        if args:
            cmd.extend(args)
        
        logger.info(f"Running script: {script_name}")
        return self._run_command(cmd, env=env)
    
    def create_playbook(self, name: str, content: str) -> Dict[str, Any]:
        """Create a new playbook"""
        playbook_path = self.playbooks_dir / f"{name}.yml"
        
        try:
            # Validate YAML
            yaml.safe_load(content)
            
            # Write playbook
            with open(playbook_path, 'w') as f:
                f.write(content)
            
            logger.info(f"Created playbook: {name}")
            return {
                'success': True,
                'path': str(playbook_path),
                'message': f"Playbook '{name}' created successfully"
            }
            
        except yaml.YAMLError as e:
            return {
                'success': False,
                'error': f"Invalid YAML: {e}"
            }
        except Exception as e:
            return {
                'success': False,
                'error': f"Failed to create playbook: {e}"
            }
    
    def validate_playbook(self, playbook_name: str) -> Dict[str, Any]:
        """Validate an Ansible playbook syntax"""
        playbook_path = self.playbooks_dir / f"{playbook_name}.yml"
        
        if not playbook_path.exists():
            return {
                'success': False,
                'error': f"Playbook '{playbook_name}' not found"
            }
        
        cmd = ["ansible-playbook", str(playbook_path), "--syntax-check"]
        
        if self.inventory and Path(self.inventory).exists():
            cmd.extend(["-i", str(self.inventory)])
        
        result = self._run_command(cmd)
        
        if result['success']:
            result['message'] = f"Playbook '{playbook_name}' syntax is valid"
        
        return result