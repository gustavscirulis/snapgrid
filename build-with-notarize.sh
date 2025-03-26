#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  echo "Loading Apple credentials from .env file..."
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found. Please create one with your Apple credentials."
  exit 1
fi

# Build and notarize
npm run electron:build 