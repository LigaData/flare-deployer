#!/usr/bin/env bash
# Runs Google's verification (install into a throwaway namespace, run the tester pod, uninstall)
# against the pushed deployer, with the current kubectl context. Usage: 30-verify.sh [extra mpdev args]
. "$(dirname "$0")/env.sh"
command -v mpdev >/dev/null || { echo "mpdev not installed: docker run gcr.io/cloud-marketplace-tools/k8s/dev cat /scripts/dev > ~/bin/mpdev && chmod +x ~/bin/mpdev"; exit 1; }
mpdev /scripts/verify --deployer="$DEPLOYER:$MP_TRACK" "$@"
