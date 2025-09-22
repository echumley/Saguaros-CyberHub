#!/bin/bash

# Exit on any error
set -e

# List of target hosts
hosts="nodes.txt"

# Path to the SSH public key
public_key="/Users/ethan/.ssh/saguaros-ansible-key.pub"

# Check if hosts file exists
if [[ ! -f "$hosts" ]]; then
    echo "Error: Hosts file '$hosts' not found!"
    exit 1
fi

# Check if public key exists
if [[ ! -f "$public_key" ]]; then
    echo "Error: Public key file '$public_key' not found!"
    exit 1
fi

echo "Starting SSH key distribution to hosts listed in $hosts"
echo "Using public key: $public_key"
echo "----------------------------------------"

# Loop through each host and copy the public key
success_count=0
failure_count=0

while IFS= read -r host; do
  # Skip empty lines and comments
  [[ -z "$host" || "$host" =~ ^[[:space:]]*# ]] && continue
  
  echo "Attempting to copy SSH key to $host..."
  
  # Execute ssh-copy-id and check its exit status
  if ssh-copy-id -o PubkeyAuthentication=no -o ConnectTimeout=10 -f -i "$public_key" root@"$host"; then
    echo "✓ SSH key successfully copied to $host."
    ((success_count++))
  else
    echo "✗ Failed to copy SSH key to $host."
    ((failure_count++))
  fi
  echo "----------------------------------------"
done < "$hosts"

echo "SSH key copy operation completed."
echo "Successful: $success_count hosts"
echo "Failed: $failure_count hosts"