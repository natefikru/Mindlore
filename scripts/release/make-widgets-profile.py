#!/usr/bin/python3
# Registers the widget extension's bundle ID and makes its App Store profile through the App Store
# Connect API, then loads the profile into the repo's secrets for release.yml. Rerun it when the
# profile expires (a year) or the distribution certificate is replaced; it reuses the bundle ID and
# replaces the profile.
#
#   scripts/release/make-widgets-profile.py <AuthKey_XXXX.p8> <issuer-id>
#
# The API key is the one set-secrets.sh loads (App Store Connect, Users and Access, Integrations);
# the issuer ID is shown at the top of that page. Uses /usr/bin/python3 and openssl only.
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

BUNDLE_ID = "com.natefikru.mindlore.widgets"
PROFILE_NAME = "Mindlore Widgets App Store"
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    # ES256 wants r and s as two 32-byte integers; openssl writes an ASN.1 SEQUENCE of INTEGERs.
    def read_int(buf, i):
        assert buf[i] == 0x02
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), i + 2 + length
    i = 2 if der[1] < 0x80 else 3
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r + s


def token(p8: str, key_id: str, issuer: str) -> str:
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", p8], input=signing_input, capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


def call(method, path, jwt, body=None):
    request = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None)
    request.add_header("Authorization", f"Bearer {jwt}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        sys.exit(f"{method} {path} failed: {error.code} {error.read().decode()}")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: make-widgets-profile.py <AuthKey_XXXX.p8> <issuer-id>")
    p8, issuer = sys.argv[1], sys.argv[2]
    key_id = os.path.basename(p8).removesuffix(".p8").removeprefix("AuthKey_")
    jwt = token(p8, key_id, issuer)

    found = call("GET", f"/bundleIds?filter[identifier]={BUNDLE_ID}", jwt)["data"]
    found = [b for b in found if b["attributes"]["identifier"] == BUNDLE_ID]
    if found:
        bundle = found[0]["id"]
        print(f"Bundle ID {BUNDLE_ID} already registered")
    else:
        bundle = call("POST", "/bundleIds", jwt, {"data": {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "Mindlore Widgets", "platform": "IOS"}}})["data"]["id"]
        print(f"Registered {BUNDLE_ID}")

    certificates = [c for c in call("GET", "/certificates?limit=200", jwt)["data"]
                    if c["attributes"]["certificateType"] in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
    if not certificates:
        sys.exit("No distribution certificate on the team")
    # The newest one is the one set-secrets.sh loaded, unless an older one was made since.
    certificates.sort(key=lambda c: c["attributes"]["expirationDate"], reverse=True)
    certificate = certificates[0]
    print(f"Signing with {certificate['attributes']['name']} (expires {certificate['attributes']['expirationDate'][:10]})")

    for old in call("GET", f"/profiles?filter[name]={urllib.parse.quote(PROFILE_NAME)}", jwt)["data"]:
        call("DELETE", f"/profiles/{old['id']}", jwt)
        print("Replaced the previous profile")
    profile = call("POST", "/profiles", jwt, {"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle}},
            "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
        },
    }})["data"]
    content = profile["attributes"]["profileContent"]

    with tempfile.NamedTemporaryFile(suffix=".mobileprovision", delete=False) as file:
        file.write(base64.b64decode(content))
    subprocess.run(["gh", "secret", "set", "APPSTORE_WIDGETS_PROFILE_BASE64", "--body", content], check=True)
    print(f"Profile \"{PROFILE_NAME}\" made and saved as APPSTORE_WIDGETS_PROFILE_BASE64 ({file.name})")


if __name__ == "__main__":
    import urllib.parse
    main()
