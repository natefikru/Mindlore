#!/bin/bash
# Loads the signing material release.yml needs into the GitHub repo and switches releases on.
#
#   scripts/release/set-secrets.sh <distribution.p12> <profile.mobileprovision> <AuthKey_XXXX.p8> <issuer-id>
#
# The p12's password is asked for, never passed on the command line. The API key ID is read from
# the .p8's file name (AuthKey_<id>.p8, as App Store Connect names it). Rerun it whenever the
# profile is regenerated (a new capability, or the yearly expiry); it overwrites what is there.
set -euo pipefail

if [[ $# -ne 4 ]]; then
    sed -n 4p "$0" | sed 's/^# *//' >&2
    exit 64
fi
p12="$1" profile="$2" p8="$3" issuer="$4"
team_id="7DZBU56KUA"
bundle_id="com.natefikru.mindlore"

for f in "$p12" "$profile" "$p8"; do
    [[ -f "$f" ]] || { echo "No such file: $f" >&2; exit 66; }
done

key_id="$(basename "$p8" .p8)"
key_id="${key_id#AuthKey_}"
[[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] || { echo "Can't read a key ID from $(basename "$p8"); expected AuthKey_<ID>.p8" >&2; exit 65; }

# Refuse a profile that would only fail on the runner.
plist="$(mktemp)"
trap 'rm -f "$plist"' EXIT
security cms -D -i "$profile" > "$plist"
app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist")"
name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist")"
expires="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$plist")"
if [[ "$app_id" != "$team_id.$bundle_id" ]]; then
    echo "Profile is for $app_id, not $team_id.$bundle_id" >&2
    exit 65
fi
if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist" >/dev/null 2>&1; then
    echo "\"$name\" lists devices, so it is a development or ad hoc profile. Make an App Store Connect one." >&2
    exit 65
fi
echo "Profile \"$name\", expires $expires"

read -r -s -p "Password for $(basename "$p12"): " p12_password
echo
# Imported into a throwaway keychain, the same way the runner will, so a p12 that works here works
# there; openssl can't be trusted for this, since macOS ships LibreSSL and OpenSSL 3 needs -legacy.
check_keychain="$(mktemp -d)/check.keychain-db"
trap 'rm -f "$plist"; security delete-keychain "$check_keychain" 2>/dev/null || true' EXIT
security create-keychain -p check "$check_keychain"
security import "$p12" -k "$check_keychain" -P "$p12_password" >/dev/null 2>&1 \
    || { echo "Couldn't import $(basename "$p12"): wrong password, or not a p12." >&2; exit 65; }
security find-identity -v -p codesigning "$check_keychain" | grep -q "Apple Distribution" \
    || { echo "$(basename "$p12") holds no Apple Distribution identity." >&2; exit 65; }

gh secret set APPLE_DISTRIBUTION_P12_BASE64 --body "$(base64 -i "$p12")"
gh secret set APPLE_DISTRIBUTION_P12_PASSWORD --body "$p12_password"
gh secret set APPSTORE_PROFILE_BASE64 --body "$(base64 -i "$profile")"
gh secret set ASC_API_KEY_P8 < "$p8"
gh secret set ASC_KEY_ID --body "$key_id"
gh secret set ASC_ISSUER_ID --body "$issuer"
gh variable set APPLE_TEAM_ID --body "$team_id"
gh variable set RELEASE_ENABLED --body "true"

echo "Done. Start a first upload with: gh workflow run release.yml --ref main"
