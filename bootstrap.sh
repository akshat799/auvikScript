set -e

REPO_URL="https://raw.githubusercontent.com/akshat799/auvikScript/main"

echo "Checking Docker installation..."

if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
else
  echo "Docker already installed."
fi

if ! command -v docker-compose &> /dev/null; then
  echo "Docker Compose not found. Installing..."
  sudo apt-get install -y docker-compose
else
  echo "Docker Compose already installed."
fi

curl -fsSL "$REPO_URL/install.sh" -o install.sh
curl -fsSL "$REPO_URL/.env.gpg" -o .env.gpg

echo "Decrypting .env..."
gpg --quiet --batch --yes --passphrase "$GPG_PASSPHRASE" --decrypt .env.gpg > .env

set -o allexport
source .env
set +o allexport

shred -u .env.gpg
shred -u .env


chmod +x install.sh
sudo -E ./install.sh
