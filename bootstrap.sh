set -e

REPO_URL="https://raw.githubusercontent.com/akshat799/auvikScript/main"

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
