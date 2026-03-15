#!/bin/bash
set -e

JOIN_SCRIPT=/vagrant/join.sh

if [ -f "${JOIN_SCRIPT}" ]; then
  bash "${JOIN_SCRIPT}" --v=5
else
  echo "Join script ${JOIN_SCRIPT} not found. Ensure the master has been provisioned."
  exit 1
fi
