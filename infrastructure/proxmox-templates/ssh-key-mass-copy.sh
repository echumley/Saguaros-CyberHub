#!/bin/bash

# List of target hosts
hosts=(
"10.1.10.99"
"10.1.10.232"
"10.1.10.72"
"10.1.10.73"
"10.1.10.124")

# Path to the SSH public key
public_key="/Users/ethan/.ssh/saguaros-ansible-key.pub"

# Loop through each host and copy the public key
for host in "${hosts[@]}"; do
  echo "Attempting to copy SSH key to $host..."
  
  # Execute ssh-copy-id and check its exit status
  if ssh-copy-id -f -i "$public_key" cactus-admin@"$host"; then
    echo "SSH key successfully copied to $host."
  else
    echo "Failed to copy SSH key to $host."
  fi
done

echo "SSH key copy operation completed."