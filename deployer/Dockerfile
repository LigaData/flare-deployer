# Data Flare Marketplace deployer (Kubernetes app type). The onbuild base packages ./chart/* into
# /data/chart, copies ./schema.yaml to /data/schema.yaml and ./apptest to /data-test. Marketplace runs
# this image as a Job in the customer's cluster: it renders the chart with the parameters from the
# console form and applies the result.
FROM gcr.io/cloud-marketplace-tools/k8s/deployer_helm/onbuild
# deploy_with_tests.sh waits WAIT_FOR_READY_TIMEOUT seconds (default 300) for every Application component
# to become ready. Flare starts six JVMs behind init containers and a setup job that waits for the UI
# and the environment master; on a fresh cluster this takes 10-15 minutes.
ENV WAIT_FOR_READY_TIMEOUT=1500
ENV TESTER_TIMEOUT=600
