# Post-install setup for Data Flare: waits for the web UI and the environment masters, registers each
# environment in the UI as an external environment and creates the pipeline user. Idempotent.
import base64, json, os, sys, time, urllib.error, urllib.request

UI = os.environ["UI_URL"].rstrip("/")
DEADLINE = time.time() + int(os.environ.get("WAIT_SECONDS", "1800"))


def call(path, data=None, token=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(UI + path, data=body, method="POST" if body else "GET")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            d = json.loads(e.read().decode() or "{}")
        except Exception:
            d = {}
        d.setdefault("httpCode", e.code)
        return d


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


def b64(s):
    return base64.b64encode(s.encode()).decode()


def read_secret(path):
    with open(path) as f:
        return f.read().strip()


envs = json.loads(os.environ.get("ENVIRONMENTS", "[]"))
wait_http(UI + "/", "web UI")
def env_url(e):
    return e.get("url") or "http://flaredriver.%s.svc.cluster.local:10001/DIEnvService" % e["ns"]


for e in envs:
    wait_http(env_url(e) + "/", "environment " + e["name"])

token = None
admin_pw = read_secret("/uisecrets/admin")
while time.time() < DEADLINE and not token:
    r = call("/authentication/login", {"email": b64(os.environ["ADMIN_EMAIL"]), "password": b64(admin_pw)})
    token = (r.get("data") or {}).get("token") if isinstance(r.get("data"), dict) else r.get("token")
    if not token:
        print("administrator login not accepted yet:", str(r)[:120]); time.sleep(15)
if not token:
    sys.exit("could not log in to the web UI as %s with the password in Secret ligadata-ui-users (key admin). "
             "If this installation uses a database that already holds Data Flare users, set ui.adminPassword "
             "(Terraform: admin_password) to the administrator's current password." % os.environ["ADMIN_EMAIL"])

registered = {x["name"] for x in items(call("/environments/getEnvironmentsInfo", token=token))}
for e in envs:
    if e["name"] in registered:
        print("environment already registered:", e["name"]); continue
    r = call("/environments/connectToEnvironment", {
        "name": e["name"], "description": "Data Flare environment " + e["name"],
        "envType": e["type"], "clusterType": "External", "clusterId": "",
        "externalUrl": env_url(e),
        "secretKey": read_secret("/envsecrets/" + e["name"])}, token=token)
    print("register environment", e["name"], "->", r.get("message") or r.get("statusMsg") or r)
    if str(r.get("httpCode", "200")) != "200":
        sys.exit("environment registration failed for " + e["name"])

pu = json.loads(os.environ.get("PIPELINE_USER") or "null")
if pu:
    roles = items(call("/role/getRoles", token=token))
    role = next((x["id"] for x in roles if x.get("name") == pu["roleName"]), None)
    if not role:
        sys.exit("role %s not found in the UI" % pu["roleName"])
    r = call("/user/createUser", {
        "userName": pu["userName"], "firstName": pu["firstName"], "lastName": pu["lastName"],
        "email": pu["email"], "roleId": role, "isActive": True,
        "password": read_secret("/uisecrets/pipelineUser"), "categoryIds": []}, token=token)
    msg = str(r.get("message") or r.get("statusMsg") or "")
    if str(r.get("httpCode", "200")) == "200" or "already exists" in msg.lower():
        print("pipeline user", pu["userName"], "->", msg or "created")
    else:
        sys.exit("pipeline user creation failed: " + json.dumps(r)[:200])
print("setup complete")
