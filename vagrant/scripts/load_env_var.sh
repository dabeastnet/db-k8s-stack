#!/usr/bin/env bash
set -euo pipefail
export DB_HOST=db-postgres
export DB_PORT=5432
export DB_NAME=demo
# ENV_FILE=".db.env"

read -rp "Enter DB_USER: " DB_USER
while [[ -z "${DB_USER}" ]]; do
  read -rp "DB_USER cannot be empty. Enter DB_USER: " DB_USER
done

read -rsp "Enter DB_PASSWORD: " DB_PASSWORD
echo
while [[ -z "${DB_PASSWORD}" ]]; do
  read -rsp "DB_PASSWORD cannot be empty. Enter DB_PASSWORD: " DB_PASSWORD
  echo
done

# cat > "$ENV_FILE" <<EOF
# export DB_USER='${DB_USER//\'/\'\\\'\'}'
# export DB_PASSWORD='${DB_PASSWORD//\'/\'\\\'\'}'
# EOF

# chmod 600 "$ENV_FILE"

export DB_USER
export DB_PASSWORD

# echo "Variables saved to $ENV_FILE"
echo "DB_USER and DB_PASSWORD are available in the current shell."
# echo "To load them later, run: source $ENV_FILE"