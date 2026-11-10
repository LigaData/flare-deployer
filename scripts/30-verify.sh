#!/usr/bin/env bash
# Runs Google's verification (install into a throwaway namespace, run the tester pod, uninstall)
# against the pushed deployer, with the current kubectl context. Usage: 30-verify.sh [extra mpdev args]
. "$(dirname "$0")/env.sh"
export PATH="$HOME/bin:$PATH"
command -v mpdev >/dev/null || { echo "mpdev not installed: docker run gcr.io/cloud-marketplace-tools/k8s/dev cat /scripts/dev > ~/bin/mpdev && chmod +x ~/bin/mpdev"; exit 1; }
# mpdev waits 600 s for the deployer Job by default; the image waits up to WAIT_FOR_READY_TIMEOUT (1500 s) for
# the application, so give the Job room to use it (Google's own harness waits longer than 25 min).
mpdev /scripts/verify --deployer="$DEPLOYER:$MP_TRACK" --wait_timeout=1800 "$@"
