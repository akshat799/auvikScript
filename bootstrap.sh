#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/akshat799/auvikScript/main"

echo "Checking Docker installation..."

if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y docker.io

  if command -v systemctl &> /dev/null && systemctl list-units --type=service &> /dev/null; then
    echo "Starting Docker using systemctl..."
    sudo systemctl enable --now docker
  else
    echo "systemctl not available. Starting Docker manually..."
    sudo service docker start 2>/dev/null || sudo nohup dockerd > /var/log/dockerd.log 2>&1 &
    sleep 5
  fi
else
  echo "Docker already installed."
fi

echo "Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
  echo "Installing Docker Compose..."
  sudo apt-get install -y docker-compose
else
  echo "Docker Compose already installed."
fi

echo "Checking for OpenSCAP (oscap)..."
if ! command -v oscap &> /dev/null; then
  echo "Installing OpenSCAP tools..."
  sudo apt-get update
sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y universe
  sudo apt-get update

  sudo apt-get install -y libopenscap8 scap-security-guide
else
  echo "OpenSCAP is already installed."
fi

echo "Downloading installer and secrets..."
curl -fsSL "$REPO_URL/install.sh" -o install.sh
curl -fsSL "$REPO_URL/.env.gpg" -o .env.gpg

echo "Decrypting .env..."
if [ -z "$GPG_PASSPHRASE" ]; then
  echo "GPG_PASSPHRASE not set. Aborting."
  exit 1
fi
echo "Decrypting .env.gpg using GPG_PASSPHRASE..."

gpg --quiet --batch --yes --passphrase "$GPG_PASSPHRASE" --decrypt .env.gpg > .env

echo "Decryption complete. Setting up environment variables..."
set -o allexport
source .env
set +o allexport

echo "Cleaning up decrypted secrets..."
shred -u .env.gpg
shred -u .env

echo "Running installer..."
chmod +x install.sh
sudo -E ./install.sh

echo "Installation complete."
