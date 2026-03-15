#!/bin/bash
# Create a ZIP archive of the entire repository for submission.

set -e

ARCHIVE_NAME="db-k8s-stack.zip"

echo "Creating $ARCHIVE_NAME..."
rm -f "$ARCHIVE_NAME"
zip -r "$ARCHIVE_NAME" . -x "*.git*" -x "$ARCHIVE_NAME" -x "vendor/*" -x "node_modules/*" -x "*.pyc" -x "__pycache__/*"

echo "Archive created: $ARCHIVE_NAME"