#### What this change does / why

#### Checklist
- [ ] `helm lint deployer/chart/data-flare` passes and CI is green
- [ ] `deployer/schema.yaml` `publishedVersion`, `Chart.yaml` `appVersion` and the release tag agree (MAJOR.MINOR.PATCH)
- [ ] Every new image reference goes through `values.yaml` and is declared under `x-google-marketplace.images`
- [ ] `mpdev verify` run against the rebuilt deployer (paste the result)
- [ ] `USER_GUIDE.md` and `CHANGELOG.md` updated
