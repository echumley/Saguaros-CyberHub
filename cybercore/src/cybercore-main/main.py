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
            message="Start Tasks:",
            choices=["- Start Task A", "- Start Task B", "- Back"],
            **COMMON,
        ).execute()  # type: ignore

        if choice == "- Back":
            return
        elif choice == "- Start Task A":
            print("Starting Task A...\n")
        elif choice == "- Start Task B":
            print("Starting Task B...\n")


def n8n_menu():
    while True:
        choice = inquirer.select(  # type: ignore
            message="n8n Menu:",
            choices=["- Trigger workflow (by ID)", "- List workflows (stub)", "- Back"],
            **COMMON,
        ).execute()  # type: ignore

        if choice == "- Back":
            return
        elif choice == "- Trigger workflow (by ID)":
            wid = inquirer.text(message="Enter workflow ID:", **COMMON).execute()  # type: ignore
            print(f"Triggering n8n workflow {wid} (stub)…\n")
        elif choice == "- List workflows (stub)":
            print("Listing workflows… (stub)\n")


def user_management_menu():
    while True:
        choice = inquirer.select(  # type: ignore
            message="User Management:",
            choices=["- Create user (stub)", "- List users (stub)", "- Back"],
            **COMMON,
        ).execute()

        if choice == "- Back":
            return
        elif choice == "- Create user (stub)":
            username = inquirer.text(message="Username:", **COMMON).execute()  # type: ignore
            print(f"Creating user {username}… (stub)\n")
        elif choice == "- List users (stub)":
            print("Users:\n  - alice\n  - bob\n(Stub)\n")


# ---------- Main menu ----------

def main():
    print(pyfiglet.figlet_format("CyberHub", font="larry3d"))

    actions = {
        "- Service Status": service_status_menu,
        "- Start Tasks": start_tasks_menu,
        "- N8n Menu": n8n_menu,
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
        sys.exit(130)