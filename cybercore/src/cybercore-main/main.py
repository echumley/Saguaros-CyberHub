#!/usr/bin/env python3

# chmod +x main.py
# mkdir -p ~/.local/bin
# ln -s "$PWD/main.py" ~/.local/bin/cybercore   # command name 'cybercore'
### ensure ~/.local/bin is on PATH
# echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

from InquirerPy import inquirer
from InquirerPy.utils import get_style
import pyfiglet
import subprocess, sys
import os
import logging
from pathlib import Path

# Add the parent directory to sys.path for imports
sys.path.insert(0, str(Path(__file__).parent))

# Import our modules
from config import DB_CONFIG, N8N_CONFIG, ANSIBLE_CONFIG
from modules.db import DatabaseManager, UserManager
from modules.n8n_api import N8nClient, N8nCLI
from modules.ansible_runner import AnsibleRunner

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize services
try:
    db_manager = DatabaseManager(DB_CONFIG)
    user_manager = UserManager(db_manager)
    n8n_client = N8nClient(N8N_CONFIG)
    n8n_cli = N8nCLI()
    ansible_runner = AnsibleRunner(ANSIBLE_CONFIG)
except Exception as e:
    logger.error(f"Failed to initialize services: {e}")
    print(f"Error: Failed to initialize services. Please check your configuration.")
    print(f"Details: {e}")
    sys.exit(1)

# Style: green bang + blue menu highlight
STYLE = get_style({
    "questionmark": "#00ff00 bold",   # green "!"
    "answermark":  "#00ff00 bold",    # keep green "!" after selection
    "pointer":     "#00aaff bold",    # blue arrow/cursor
    "highlighted": "#00aaff bold",    # blue highlight while navigating
    "selected":    "#00aaff",         # blue for the chosen item
    "answer":      "#ffffff bold",    # echoed answer text
})

COMMON = {"qmark": "!", "amark": "!", "style": STYLE}  # reuse on all prompts

# Style: Menu coloring
BLUE = "\033[94m"
RESET = "\033[0m"

# ---------- Submenu helpers ----------

def service_status_menu():
    while True:
        action = inquirer.select(  # type: ignore
            message="Service/Module Status:",
            choices=[
                "- Show running containers",
                "- Show all containers",
                "- Show CyberHub modules",
                "- Back",
            ],
            **COMMON,
        ).execute()  # type: ignore

        if action == "- Back":
            return

        if action == "- Show CyberHub modules":
            modules = [
                ("CyberHub", "cybercore/"),
                ("CyberCore", "cybercore/"),
                ("CyberLabs", "cyberlabs/"),
                ("The Crucible", "the-crucible/"),
                ("The Forge", "the-forge/"),
                ("Saguaros University", "saguaros-university/"),
                ("The Archive", "the-archive/"),
                ("Saguaros Wiki", "saguaros-wiki/"),
            ]
            print(f"\n{BLUE}--------- CyberHub Modules ---------{RESET}")
            for name, path in modules:
                # Navigate from cybercore/src/cybercore-main/ to the root directory
                root_dir = os.path.join(os.path.dirname(__file__), "..", "..", "..")
                module_path = os.path.join(root_dir, path)
                installed = "Installed" if os.path.isdir(module_path) else "Not Installed"
                print(f"  {name}: {installed}")
            print()
            continue

        show_all = action == "- Show all containers"
        cmd = ["docker", "ps"] + (["--all"] if show_all else []) + ["--format", "{{.Names}}\t{{.Status}}\t{{.Ports}}"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        print(f"\n{BLUE}--------- Services/Modules ---------{RESET}")
        lines = [l for l in result.stdout.strip().split("\n") if l.strip()]
        if not lines:
            print("(no containers match)\n")
            continue

        for line in lines:
            parts = line.split("\t")
            name = parts[0] if len(parts) > 0 else "?"
            status = parts[1] if len(parts) > 1 else "?"
            ports = parts[2] if len(parts) > 2 else ""
            print(f"  Name: {name}\n    Status: {status}\n    Ports: {ports or 'N/A'}\n")


def start_tasks_menu():
    while True:
        choice = inquirer.select(  # type: ignore
            message="Ansible & Automation:",
            choices=[
                "- List playbooks",
                "- Run playbook",
                "- Run script",
                "- Create playbook",
                "- Validate playbook",
                "- Back"
            ],
            **COMMON,
        ).execute()  # type: ignore

        if choice == "- Back":
            return
            
        elif choice == "- List playbooks":
            playbooks = ansible_runner.list_playbooks()
            if playbooks:
                print(f"\n{BLUE}--------- Ansible Playbooks ---------{RESET}")
                for pb in playbooks:
                    print(f"  Name: {pb['name']}")
                    print(f"    Path: {pb['path']}")
                    print(f"    Description: {pb['description']}")
                    print()
            else:
                print("\nNo playbooks found.\n")
                
        elif choice == "- Run playbook":
            playbook_name = inquirer.text(message="Playbook name or path:", **COMMON).execute()  # type: ignore
            
            # Optional parameters
            add_params = inquirer.confirm(message="Add parameters?", default=False, **COMMON).execute()  # type: ignore
            
            extra_vars = None
            tags = None
            limit = None
            check = False
            verbose = 0
            
            if add_params:
                # Extra variables
                vars_input = inquirer.text(message="Extra variables (JSON format, optional):", **COMMON).execute()  # type: ignore
                if vars_input:
                    try:
                        import json
                        extra_vars = json.loads(vars_input)
                    except:
                        print("Invalid JSON format for variables")
                
                # Tags
                tags_input = inquirer.text(message="Tags (comma-separated, optional):", **COMMON).execute()  # type: ignore
                if tags_input:
                    tags = [t.strip() for t in tags_input.split(',')]
                
                # Limit
                limit = inquirer.text(message="Limit hosts (optional):", **COMMON).execute()  # type: ignore
                if not limit:
                    limit = None
                
                # Check mode
                check = inquirer.confirm(message="Run in check mode?", default=False, **COMMON).execute()  # type: ignore
                
                # Verbosity
                verbose = inquirer.select(  # type: ignore
                    message="Verbosity level:",
                    choices=[0, 1, 2, 3, 4],
                    default=0,
                    **COMMON,
                ).execute()  # type: ignore
            
            print(f"\nRunning playbook: {playbook_name}...")
            result = ansible_runner.run_playbook(
                playbook_name, 
                extra_vars=extra_vars,
                tags=tags,
                limit=limit,
                check=check,
                verbose=verbose
            )
            
            if result['success']:
                print(f"✓ Playbook executed successfully!")
                if result.get('summary'):
                    print(f"\nSummary:")
                    for key, value in result['summary'].items():
                        print(f"  {key}: {value}")
            else:
                print(f"✗ Playbook execution failed")
                if result.get('error'):
                    print(f"Error: {result['error']}")
            
            if result.get('stdout'):
                show_output = inquirer.confirm(message="Show full output?", default=False, **COMMON).execute()  # type: ignore
                if show_output:
                    print("\n--- Output ---")
                    print(result['stdout'])
                    print("--- End ---")
            print()
            
        elif choice == "- Run script":
            script_name = inquirer.text(message="Script name or path:", **COMMON).execute()  # type: ignore
            args_input = inquirer.text(message="Arguments (space-separated, optional):", **COMMON).execute()  # type: ignore
            
            args = args_input.split() if args_input else None
            
            print(f"\nRunning script: {script_name}...")
            result = ansible_runner.run_script(script_name, args=args)
            
            if result['success']:
                print(f"✓ Script executed successfully!")
                if result['stdout']:
                    print("\n--- Output ---")
                    print(result['stdout'])
                    print("--- End ---")
            else:
                print(f"✗ Script execution failed")
                if result.get('error'):
                    print(f"Error: {result['error']}")
                if result['stderr']:
                    print(f"Error output: {result['stderr']}")
            print()
            
        elif choice == "- Create playbook":
            name = inquirer.text(message="Playbook name (without .yml):", **COMMON).execute()  # type: ignore
            
            print("\nEnter playbook content (YAML format).")
            print("Type 'END' on a new line when done:\n")
            
            lines = []
            while True:
                line = input()
                if line == 'END':
                    break
                lines.append(line)
            
            content = '\n'.join(lines)
            
            result = ansible_runner.create_playbook(name, content)
            if result['success']:
                print(f"\n✓ Playbook '{name}' created successfully!")
                print(f"Path: {result['path']}\n")
            else:
                print(f"\n✗ Failed to create playbook: {result['error']}\n")
                
        elif choice == "- Validate playbook":
            playbook_name = inquirer.text(message="Playbook name:", **COMMON).execute()  # type: ignore
            
            print(f"\nValidating playbook: {playbook_name}...")
            result = ansible_runner.validate_playbook(playbook_name)
            
            if result['success']:
                print(f"✓ {result['message']}\n")
            else:
                print(f"✗ Validation failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
            print()


def n8n_menu():
    while True:
        choice = inquirer.select(  # type: ignore
            message="n8n Menu:",
            choices=[
                "- Trigger workflow (by ID)",
                "- List workflows",
                "- Execute workflow (CLI)",
                "- Export workflow",
                "- Import workflow",
                "- Get n8n status",
                "- Back"
            ],
            **COMMON,
        ).execute()  # type: ignore

        if choice == "- Back":
            return
        elif choice == "- Trigger workflow (by ID)":
            wid = inquirer.text(message="Enter workflow ID:", **COMMON).execute()  # type: ignore
            print(f"\nTriggering workflow {wid}...")
            result = n8n_client.trigger_workflow(wid)
            if result['success']:
                print(f"✓ Workflow triggered successfully!")
                if result.get('response'):
                    print(f"Response: {result['response']}")
            else:
                print(f"✗ Failed to trigger workflow: {result.get('error', 'Unknown error')}")
            print()
            
        elif choice == "- List workflows":
            print("\nFetching workflows...")
            workflows = n8n_client.list_workflows()
            if workflows:
                print(f"\n{BLUE}--------- N8n Workflows ---------{RESET}")
                for wf in workflows:
                    status = "Active" if wf.get('active') else "Inactive"
                    print(f"  ID: {wf['id']}")
                    print(f"    Name: {wf['name']}")
                    print(f"    Status: {status}")
                    if wf.get('webhook_id'):
                        print(f"    Webhook: {wf['webhook_id']}")
                    print()
            else:
                print("No workflows found.\n")
                
        elif choice == "- Execute workflow (CLI)":
            wid = inquirer.text(message="Enter workflow ID:", **COMMON).execute()  # type: ignore
            print(f"\nExecuting workflow {wid} via CLI...")
            result = n8n_cli.execute_workflow(wid)
            if result['success']:
                print(f"✓ Workflow executed successfully!")
                if result['stdout']:
                    print(f"Output: {result['stdout']}")
            else:
                print(f"✗ Failed to execute workflow")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
            print()
            
        elif choice == "- Export workflow":
            wid = inquirer.text(message="Enter workflow ID:", **COMMON).execute()  # type: ignore
            filename = inquirer.text(message="Output filename (optional):", **COMMON).execute()  # type: ignore
            print(f"\nExporting workflow {wid}...")
            result = n8n_cli.export_workflow(wid, filename if filename else None)
            if result['success']:
                print(f"✓ Workflow exported successfully!")
                if result['stdout']:
                    print(f"Output: {result['stdout']}")
            else:
                print(f"✗ Failed to export workflow")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
            print()
            
        elif choice == "- Import workflow":
            filename = inquirer.text(message="Enter JSON file path:", **COMMON).execute()  # type: ignore
            print(f"\nImporting workflow from {filename}...")
            result = n8n_cli.import_workflow(filename)
            if result['success']:
                print(f"✓ Workflow imported successfully!")
                if result['stdout']:
                    print(f"Output: {result['stdout']}")
            else:
                print(f"✗ Failed to import workflow")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
            print()
            
        elif choice == "- Get n8n status":
            print("\nGetting n8n status...")
            result = n8n_cli.get_status()
            if result['success']:
                print(f"✓ N8n Status:")
                if result['stdout']:
                    print(result['stdout'])
            else:
                print(f"✗ Failed to get status")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
            print()


def user_management_menu():
    while True:
        choice = inquirer.select(  # type: ignore
            message="User Management:",
            choices=[
                "- List users",
                "- Create user",
                "- View user details",
                "- Update user",
                "- Delete user",
                "- Back"
            ],
            **COMMON,
        ).execute()

        if choice == "- Back":
            return
            
        elif choice == "- List users":
            try:
                users = user_manager.list_users()
                if users:
                    print(f"\n{BLUE}--------- Users ---------{RESET}")
                    for user in users:
                        print(f"  Username: {user['username']}")
                        if user.get('email'):
                            print(f"    Email: {user['email']}")
                        if user.get('full_name'):
                            print(f"    Name: {user['full_name']}")
                        print(f"    Status: {user['status']}")
                        print(f"    Active: {'Yes' if user['active'] else 'No'}")
                        print()
                else:
                    print("\nNo users found.\n")
            except Exception as e:
                print(f"\n✗ Error listing users: {e}\n")
                
        elif choice == "- Create user":
            username = inquirer.text(message="Username:", **COMMON).execute()  # type: ignore
            email = inquirer.text(message="Email (optional):", **COMMON).execute()  # type: ignore
            first_name = inquirer.text(message="First name (optional):", **COMMON).execute()  # type: ignore
            last_name = inquirer.text(message="Last name (optional):", **COMMON).execute()  # type: ignore
            set_password = inquirer.confirm(message="Set password?", default=False, **COMMON).execute()  # type: ignore
            
            password = None
            if set_password:
                password = inquirer.secret(message="Password:", **COMMON).execute()  # type: ignore
            
            try:
                user = user_manager.create_user(
                    username=username,
                    email=email if email else None,
                    first_name=first_name if first_name else None,
                    last_name=last_name if last_name else None,
                    password=password
                )
                print(f"\n✓ User '{username}' created successfully!\n")
            except Exception as e:
                print(f"\n✗ Error creating user: {e}\n")
                
        elif choice == "- View user details":
            username = inquirer.text(message="Username:", **COMMON).execute()  # type: ignore
            try:
                user = user_manager.get_user(username)
                if user:
                    print(f"\n{BLUE}--------- User Details ---------{RESET}")
                    for key, value in user.items():
                        if key not in ['password_hash', 'password_algo'] and value is not None:
                            print(f"  {key}: {value}")
                    print()
                else:
                    print(f"\n✗ User '{username}' not found.\n")
            except Exception as e:
                print(f"\n✗ Error: {e}\n")
                
        elif choice == "- Update user":
            username = inquirer.text(message="Username:", **COMMON).execute()  # type: ignore
            
            try:
                user = user_manager.get_user(username)
                if not user:
                    print(f"\n✗ User '{username}' not found.\n")
                    continue
                
                # Ask what to update
                update_choice = inquirer.select(  # type: ignore
                    message="What to update?",
                    choices=[
                        "Email",
                        "First name",
                        "Last name",
                        "Password",
                        "Active status",
                        "User status",
                        "Cancel"
                    ],
                    **COMMON,
                ).execute()  # type: ignore
                
                if update_choice == "Cancel":
                    continue
                
                updates = {}
                if update_choice == "Email":
                    new_email = inquirer.text(message="New email:", default=user.get('email', ''), **COMMON).execute()  # type: ignore
                    updates['email'] = new_email
                elif update_choice == "First name":
                    new_fname = inquirer.text(message="New first name:", default=user.get('first_name', ''), **COMMON).execute()  # type: ignore
                    updates['first_name'] = new_fname
                elif update_choice == "Last name":
                    new_lname = inquirer.text(message="New last name:", default=user.get('last_name', ''), **COMMON).execute()  # type: ignore
                    updates['last_name'] = new_lname
                elif update_choice == "Password":
                    new_password = inquirer.secret(message="New password:", **COMMON).execute()  # type: ignore
                    updates['password'] = new_password
                elif update_choice == "Active status":
                    is_active = inquirer.confirm(message="Active?", default=user['active'], **COMMON).execute()  # type: ignore
                    updates['active'] = is_active
                elif update_choice == "User status":
                    new_status = inquirer.select(  # type: ignore
                        message="New status:",
                        choices=['active', 'inactive', 'suspended', 'banned'],
                        default=user['status'],
                        **COMMON,
                    ).execute()  # type: ignore
                    updates['status'] = new_status
                
                if updates:
                    updated_user = user_manager.update_user(username, **updates)
                    if updated_user:
                        print(f"\n✓ User '{username}' updated successfully!\n")
                    else:
                        print(f"\n✗ Failed to update user.\n")
                        
            except Exception as e:
                print(f"\n✗ Error: {e}\n")
                
        elif choice == "- Delete user":
            username = inquirer.text(message="Username:", **COMMON).execute()  # type: ignore
            confirm = inquirer.confirm(message=f"Are you sure you want to delete user '{username}'?", default=False, **COMMON).execute()  # type: ignore
            
            if confirm:
                soft_delete = inquirer.confirm(message="Soft delete? (preserves user data)", default=True, **COMMON).execute()  # type: ignore
                try:
                    if user_manager.delete_user(username, soft_delete=soft_delete):
                        print(f"\n✓ User '{username}' deleted successfully!\n")
                    else:
                        print(f"\n✗ User '{username}' not found.\n")
                except Exception as e:
                    print(f"\n✗ Error: {e}\n")


# ---------- Main menu ----------

def main():
    print(pyfiglet.figlet_format("CyberHub", font="larry3d"))

    actions = {
        "- Service Status": service_status_menu,
        "- Ansible & Automation": start_tasks_menu,
        "- N8n Workflows": n8n_menu,
        "- User Management": user_management_menu,
        "- Exit": lambda: sys.exit(0),
    }

    while True:
        main_choice = inquirer.select(  # type: ignore
            message="Select an option from the CyberCore menu:",
            choices=list(actions.keys()),
            **COMMON,
        ).execute()  # type: ignore

        actions[main_choice]()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted.")
    finally:
        # Clean up database connections
        try:
            db_manager.close()
        except:
            pass
        sys.exit(130 if 'KeyboardInterrupt' in str(sys.exc_info()[0]) else 0)