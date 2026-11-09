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
  gcloud artifacts docker images list "$DEST/$name" --include-tags --format="value(version,tags)" 2>/dev/null \
    | awk '$2==""{print $1}' | while read -r old; do gcloud artifacts docker images delete "$DEST/$name@$old" --quiet >/dev/null 2>&1 || true; done
done
