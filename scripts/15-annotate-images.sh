#!/usr/bin/env bash
# Sets this product's service-name annotation on images in its repository and re-points the tags.
# Usage: 15-annotate-images.sh <name>...
. "$(dirname "$0")/env.sh"
[ -n "${MP_SERVICE_NAME:-}" ] || { echo "MP_SERVICE_NAME not set; skipping annotation"; exit 0; }
crane auth login us-docker.pkg.dev -u oauth2accesstoken -p "$(gcloud auth print-access-token)" >/dev/null
for name in "$@"; do
  digest=$(crane digest "$DEST/$name:$MP_TRACK")
  new=$(crane mutate -a "com.googleapis.cloudmarketplace.product.service.name=$MP_SERVICE_NAME" "$DEST/$name@$digest") \
    || { echo "annotation failed for $name (image must be a single manifest, not an index)"; exit 1; }
  new=${new##*@}
  for t in "$MP_TRACK" "$MP_VERSION"; do crane tag "$DEST/$name@$new" "$t"; done
  echo "  $name annotated -> $new"
  # Remove only the un-annotated manifest this run replaced. Never prune other untagged manifests:
  # Producer Portal pins a version to the digest it resolved at submission, and deleting that digest
  # breaks validation with "Image not found".
  [ "$new" != "$digest" ] && gcloud artifacts docker images delete "$DEST/$name@$digest" --quiet >/dev/null 2>&1 || true
done
