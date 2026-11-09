# Data Flare Marketplace deployer (Kubernetes app type). The onbuild base packages ./chart/* into
# /data/chart, copies ./schema.yaml to /data/schema.yaml and ./apptest to /data-test. Marketplace runs
# this image as a Job in the customer's cluster: it renders the chart with the parameters from the
# console form and applies the result.
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild
