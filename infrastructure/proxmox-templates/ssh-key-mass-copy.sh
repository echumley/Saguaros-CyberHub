#!/bin/bash

# List of target hosts
hosts="/path/to/file/with/IPs.txt"

# Path to the SSH public key
public_key="/home/cactus-admin/.ssh/saguaros-ansible-key.pub"

# Loop through each host and copy the public key
for host in "${hosts[@]}"; do
  echo "Attempting to copy SSH key to $host..."
  
  # Execute ssh-copy-id and check its exit status
  if ssh-copy-id -o PubkeyAuthentication=no -f -i "$public_key" cactus-admin@"$host"; then
    echo "SSH key successfully copied to $host."
  else
    echo "Failed to copy SSH key to $host."
  fi
done

echo "SSH key copy operation completed."