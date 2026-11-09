#!/usr/bin/env bash
# Copies the six product images from LigaData's staging repository (SRC_REPO) into this product's
# repository and annotates them with this product's service name. Usage: 10-copy-images.sh [name...]
. "$(dirname "$0")/env.sh"
command -v crane >/dev/null || { echo "crane not installed (brew install crane)"; exit 1; }
gcloud artifacts repositories describe "$MP_REPO" --project "$MP_PROJECT" --location us >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$MP_REPO" --project "$MP_PROJECT" --location us --repository-format docker \
    --description "Google Cloud Marketplace staging (Kubernetes app)"
crane auth login us-docker.pkg.dev -u oauth2accesstoken -p "$(gcloud auth print-access-token)" >/dev/null
names=("$@"); [ ${#names[@]} -gt 0 ] || names=(dismain disworker flare4ui seed redis postgres)
for name in "${names[@]}"; do
  echo "== $SRC_REPO/$name:$MP_TRACK -> $DEST/$name:{$MP_TRACK,$MP_VERSION}"
  crane copy "$SRC_REPO/$name:$MP_TRACK" "$DEST/$name:$MP_TRACK"
  crane tag "$DEST/$name:$MP_TRACK" "$MP_VERSION"
done
"$HERE/15-annotate-images.sh" "${names[@]}"
