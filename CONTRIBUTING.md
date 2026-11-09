# Contributing

Changes arrive by pull request against `main`; a code owner reviews and merges. CI must be green.

Before opening a pull request:

1. `helm lint deployer/chart/data-flare`.
2. Keep `deployer/schema.yaml` `publishedVersion`, `Chart.yaml` `appVersion` and the image tags in step
   (MAJOR.MINOR.PATCH; the release track is MAJOR.MINOR).
3. Build the deployer and run Google's verification on a GKE cluster:
   `scripts/20-build-deployer.sh && scripts/30-verify.sh`.
4. Update `USER_GUIDE.md` and `CHANGELOG.md`.

Issues: licensed customers should contact support@ligadata.com; GitHub issues are for the deployer
package itself.
