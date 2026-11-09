# shared by the deployer build scripts
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PKG="$(dirname "$HERE")"; ROOT="$(dirname "$PKG")"
[ -f "$PKG/marketplace.env" ] || { echo "missing $PKG/marketplace.env (copy marketplace.env.example)"; exit 1; }
set -a; . "$PKG/marketplace.env"; set +a
: "${MP_PROJECT:?}" "${MP_REPO:?}" "${MP_TRACK:?}" "${MP_VERSION:?}" "${SRC_REPO:?}"
DEST="us-docker.pkg.dev/$MP_PROJECT/$MP_REPO"
DEPLOYER="$DEST/deployer"
export COPYFILE_DISABLE=1
