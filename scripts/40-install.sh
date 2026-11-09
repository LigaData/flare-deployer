#!/usr/bin/env bash
# Installs the app the way the console does, through the deployer, into a namespace of the current
# cluster. Usage: 40-install.sh <namespace> [name] [extra JSON parameters]
. "$(dirname "$0")/env.sh"
NS=${1:?namespace}; NAME=${2:-data-flare}; EXTRA=${3:-}
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"
PARAMS=$(python3 -c "import json,sys; p={'name':sys.argv[1],'namespace':sys.argv[2]}; p.update(json.loads(sys.argv[3]) if sys.argv[3] else {}); print(json.dumps(p))" "$NAME" "$NS" "$EXTRA")
mpdev install --deployer="$DEPLOYER:$MP_TRACK" --parameters="$PARAMS"
kubectl -n "$NS" get application,pods
