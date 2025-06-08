set -e

REPO_URL="https://raw.githubusercontent.com/your-org/unified-installer/main"

curl -fsSL "$REPO_URL/install.sh" -o install.sh
curl -fsSL "$REPO_URL/.env.gpg" -o .env.gpg

echo "Decrypting .env..."
gpg --quiet --batch --yes --decrypt .env.gpg > .env

set -o allexport
source .env
set +o allexport

shred -u .env.gpg
shred -u .env


chmod +x install.sh
sudo -E ./install.sh
