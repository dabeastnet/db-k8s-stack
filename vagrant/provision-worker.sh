#!/bin/bash
set -e

JOIN_SCRIPT=/vagrant/join.sh

if [ ! -f "${JOIN_SCRIPT}" ]; then
  echo "Join script ${JOIN_SCRIPT} not found. Ensure the master has been provisioned."
  exit 1
fi

# Wait for the control plane API server to be reachable before joining.
# On fresh `vagrant up` runs all VMs boot roughly in parallel and the
# worker provisioner can start before cp1's API server is ready, causing
# the join to time out immediately.  Poll port 6443 with a short TCP
# connect timeout until it responds, then proceed with the join.
APISERVER=192.168.56.10
echo "Waiting for API server at ${APISERVER}:6443 to be reachable..."
until nc -z -w 3 "${APISERVER}" 6443 2>/dev/null; do
  echo "  API server not ready yet, retrying in 5s..."
  sleep 5
done
echo "API server is reachable. Proceeding with join."

bash "${JOIN_SCRIPT}" --v=5
