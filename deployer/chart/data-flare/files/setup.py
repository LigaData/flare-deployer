# Post-install setup for Data Flare: waits for the web UI and the environment masters, registers each
# environment in the UI as an external environment and creates the pipeline user. Idempotent, and it
# never exits non-zero before the deadline: every error (connection refused, DNS, reset, timeout, a
# non-JSON or 5xx answer while the UI is still coming up) is logged and retried, because the Marketplace
# deployer treats a failed Job as a failed installation.
import base64, json, os, sys, time, traceback, urllib.error, urllib.request

UI = os.environ["UI_URL"].rstrip("/")
DEADLINE = time.time() + int(os.environ.get("WAIT_SECONDS", "1800"))
RETRY = 15


def call(path, data=None, token=None):
    """POST/GET the UI API. Returns a dict; httpCode is the status, or 0 when no HTTP answer came back."""
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(UI + path, data=body, method="POST" if body else "GET")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode(errors="replace")
            code = r.status
    except urllib.error.HTTPError as e:
        raw, code = e.read().decode(errors="replace"), e.code
    except Exception as e:                      # URLError, socket timeout, reset, DNS
        return {"httpCode": 0, "error": str(e)}
    try:
        d = json.loads(raw or "{}")
    except ValueError:
        d = {"error": "non-JSON answer: " + raw[:120]}
    if not isinstance(d, dict):
        d = {"data": d}
    d.setdefault("httpCode", code)
    return d


def ok(d):
    return str(d.get("httpCode")) == "200"


def items(d):
    x = d.get("data", d) if isinstance(d, dict) else d
    if isinstance(x, dict):
        x = x.get("data") or x.get("entries") or []
    return x or []


def wait_http(url, what):
    while time.time() < DEADLINE:
        try:
            urllib.request.urlopen(url, timeout=10)
            print("ready:", what); return
        except urllib.error.HTTPError:
            print("ready:", what); return          # any HTTP answer means the server is up
        except Exception as e:
            print("waiting for", what, "-", e); time.sleep(10)
    sys.exit("timeout waiting for " + what)


def until_ok(what, fn, accept=lambda d: False):
    """Repeat fn() until it answers 200 (or accept(d) says the answer is fine) or the deadline passes."""
    while True:
        d = fn()
        if ok(d) or accept(d):
            return d
        code = int(d.get("httpCode") or 0)
        if 400 <= code < 500 and code not in (401, 403, 408, 429):   # the request itself is rejected; waiting will not help
            sys.exit("%s rejected by the web UI (HTTP %d): %s" % (what, code, json.dumps(d)[:300]))
        print(what, "not accepted yet:", str(d)[:160])
        if time.time() > DEADLINE:
            sys.exit("%s failed before the deadline: %s" % (what, json.dumps(d)[:300]))
        time.sleep(RETRY)


def b64(s):
    return base64.b64encode(s.encode()).decode()


def read_secret(path):
    with open(path) as f:
        return f.read().strip()


def env_url(e):
    return e.get("url") or "http://flaredriver.%s.svc.cluster.local:10001/DIEnvService" % e["ns"]


def main():
    envs = json.loads(os.environ.get("ENVIRONMENTS", "[]"))
    wait_http(UI + "/", "web UI")
    for e in envs:
        wait_http(env_url(e) + "/", "environment " + e["name"])

    admin_pw = read_secret("/uisecrets/admin")

    def login():
        r = call("/authentication/login", {"email": b64(os.environ["ADMIN_EMAIL"]), "password": b64(admin_pw)})
        data = r.get("data")
        r["token"] = data.get("token") if isinstance(data, dict) else r.get("token")
        if not r["token"]:
            r["httpCode"] = r.get("httpCode") if str(r.get("httpCode")) != "200" else 0
        return r
    r = until_ok("administrator login as %s with the password in Secret ligadata-ui-users key admin (if the database "
                 "already holds Data Flare users, set ui.adminPassword to the current administrator password)"
                 % os.environ["ADMIN_EMAIL"], login)
    token = r["token"]
    if not token:
        sys.exit("could not log in to the web UI as %s with the password in Secret ligadata-ui-users (key admin). "
                 "If this installation uses a database that already holds Data Flare users, set ui.adminPassword "
                 "to the administrator's current password." % os.environ["ADMIN_EMAIL"])

    registered = {x.get("name") for x in items(until_ok("environment list", lambda: call("/environments/getEnvironmentsInfo", token=token)))}
    for e in envs:
        if e["name"] in registered:
            print("environment already registered:", e["name"]); continue
        r = until_ok("registration of environment " + e["name"], lambda: call("/environments/connectToEnvironment", {
            "name": e["name"], "description": "Data Flare environment " + e["name"],
            "envType": e["type"], "clusterType": "External", "clusterId": "",
            "externalUrl": env_url(e),
            "secretKey": read_secret("/envsecrets/" + e["name"])}, token=token),
            accept=lambda d: "already" in str(d.get("message") or d.get("statusMsg") or "").lower())
        print("register environment", e["name"], "->", r.get("message") or r.get("statusMsg") or r.get("httpCode"))

    pu = json.loads(os.environ.get("PIPELINE_USER") or "null")
    if pu:
        roles = items(until_ok("role list", lambda: call("/role/getRoles", token=token)))
        role = next((x.get("id") for x in roles if x.get("name") == pu["roleName"]), None)
        if not role:
            sys.exit("role %s not found in the UI" % pu["roleName"])
        r = until_ok("creation of pipeline user " + pu["userName"], lambda: call("/user/createUser", {
            "userName": pu["userName"], "firstName": pu["firstName"], "lastName": pu["lastName"],
            "email": pu["email"], "roleId": role, "isActive": True,
            "password": read_secret("/uisecrets/pipelineUser"), "categoryIds": []}, token=token),
            accept=lambda d: "already exists" in str(d.get("message") or d.get("statusMsg") or "").lower())
        print("pipeline user", pu["userName"], "->", r.get("message") or r.get("statusMsg") or "created")
    print("setup complete")


while True:
    try:
        main()
        break
    except SystemExit:
        raise
    except Exception:
        traceback.print_exc()
        if time.time() > DEADLINE:
            sys.exit("setup gave up after repeated errors")
        print("retrying in", RETRY, "seconds"); time.sleep(RETRY)
