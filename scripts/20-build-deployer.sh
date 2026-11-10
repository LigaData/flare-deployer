#!/usr/bin/env bash
# Builds the deployer image (chart + schema + apptest) and pushes it as deployer:<track> and
# deployer:<version>, with the Marketplace service-name annotation. Needs gcloud + docker logged in
# and access to gcr.io/cloud-marketplace-tools (the deployer base image).
. "$(dirname "$0")/env.sh"
gcloud auth configure-docker us-docker.pkg.dev,gcr.io --quiet
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp -R "$PKG/deployer/." "$WORK/"
# point the chart defaults at the staging repository (Marketplace overrides them at deploy time)
sed -i '' -E "s#us-docker.pkg.dev/PARTNER_PROJECT/SOLUTION#$DEST#g; s#^(  solutionUrn:).*#\1 \"${MP_SOLUTION_URN:-}\"#" "$WORK/chart/data-flare/values.yaml"
sed -i '' -E "s#^(  publishedVersion:).*#\1 \"$MP_VERSION\"#" "$WORK/schema.yaml"
# the deployer requires Application spec.descriptor.version (= Chart appVersion) to equal publishedVersion
sed -i '' -E "s#^appVersion:.*#appVersion: \"$MP_VERSION\"#" "$WORK/chart/data-flare/Chart.yaml"
helm lint "$WORK/chart/data-flare"
docker build --platform linux/amd64 --provenance=false --sbom=false -t "$DEPLOYER:$MP_TRACK" -t "$DEPLOYER:$MP_VERSION" "$WORK"
docker push "$DEPLOYER:$MP_TRACK"; docker push "$DEPLOYER:$MP_VERSION"
"$HERE/15-annotate-images.sh" deployer
# schema v2 resolves every product image as <repo>/<name>:<publishedVersion>, so each version needs its tag on
# the six product images too (a tag on the existing digest; no new manifest, nothing to re-annotate)
for n in dismain disworker flare4ui seed redis postgres; do crane tag "$DEST/$n:$MP_TRACK" "$MP_VERSION" >/dev/null && echo "  $n tagged $MP_VERSION"; done
echo "deployer: $DEPLOYER   (paste in Producer Portal > Specify deployment container images; tag $MP_TRACK)"
