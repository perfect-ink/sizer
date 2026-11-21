#!/usr/bin/env bash
# Sets every GitHub Actions secret the App Store workflow needs, from this Mac:
#
#   1. Exports the "Apple Distribution" and installer identities for the team
#      (only those two) from the login keychain into a .p12 with a random password.
#   2. Finds the Mac App Store provisioning profile for the bundle ID through the
#      App Store Connect API, or creates one for that distribution certificate.
#   3. Sets MAS_CERTIFICATE_P12, MAS_CERTIFICATE_PASSWORD, MAS_PROVISIONING_PROFILE,
#      APP_STORE_CONNECT_API_KEY(_ID), APP_STORE_CONNECT_ISSUER_ID, APP_REVIEW_PHONE
#      on the GitHub repo. Values go through stdin, never the command line.
#
#   make appstore-secrets              # do it
#   make appstore-secrets DRY_RUN=1    # check everything, export and set nothing
#
# Optional environment (anything missing is found or asked for):
#   ASC_KEY_FILE      path to AuthKey_XXXXXXXXXX.p8 (default: the only one under ~/Downloads)
#   ASC_ISSUER_ID     App Store Connect → Users and Access → Integrations, above the keys
#   APP_REVIEW_PHONE  phone for App Review (blank keeps the secret already set)
#   TEAM_ID BUNDLE_ID REPO   default to the Makefile, Info.plist and this repo's origin
#
# macOS asks to allow exporting each private key from the keychain: click Allow.
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."
DRY_RUN="${DRY_RUN:-0}"
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say()  { printf '→ %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || die "Install the GitHub CLI: brew install gh"
gh auth status >/dev/null 2>&1 || die "Sign in first: gh auth login"

TEAM_ID="${TEAM_ID:-$(sed -n 's/^TEAM_ID *?= *//p' Makefile | head -1)}"
BUNDLE_ID="${BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
[ -n "$TEAM_ID" ] || die "Couldn't read TEAM_ID from the Makefile; pass TEAM_ID=…"
[ "$(gh repo view "$REPO" --json viewerPermission -q .viewerPermission)" = "ADMIN" ] \
  || die "Your GitHub account needs admin on $REPO to set secrets"
say "Team $TEAM_ID, bundle $BUNDLE_ID, repo $REPO"

# --- App Store Connect API key ---------------------------------------------
if [ -z "${ASC_KEY_FILE:-}" ]; then
  keys="$(find ~/Downloads ~/Documents -maxdepth 3 -name 'AuthKey_*.p8' 2>/dev/null || true)"
  [ "$(printf '%s' "$keys" | grep -c . || true)" = 1 ] \
    || die "Found $(printf '%s' "$keys" | grep -c . || true) AuthKey_*.p8 files; pass ASC_KEY_FILE=path"
  ASC_KEY_FILE="$keys"
fi
[ -f "$ASC_KEY_FILE" ] || die "No API key at $ASC_KEY_FILE"
ASC_KEY_ID="$(basename "$ASC_KEY_FILE" .p8)"; ASC_KEY_ID="${ASC_KEY_ID#AuthKey_}"
ok "API key $ASC_KEY_ID ($ASC_KEY_FILE)"
[ -n "${ASC_ISSUER_ID:-}" ] || read -r -p "App Store Connect Issuer ID: " ASC_ISSUER_ID </dev/tty
[ -n "$ASC_ISSUER_ID" ] || die "The Issuer ID is required"

# --- Identities in the login keychain --------------------------------------
identity_hash() {  # identity_hash REGEX -> SHA-1 of the first matching valid identity
  security find-identity -v | grep -E "\"($1): .*\\($TEAM_ID\\)\"" | head -1 | awk '{print $2}'
}
APP_HASH="$(identity_hash 'Apple Distribution|3rd Party Mac Developer Application')"
INST_HASH="$(identity_hash '3rd Party Mac Developer Installer|Mac Installer Distribution')"
[ -n "$APP_HASH" ]  || die "No Apple Distribution identity for team $TEAM_ID in the keychain"
[ -n "$INST_HASH" ] || die "No Mac Installer Distribution identity for team $TEAM_ID in the keychain"
APP_SERIAL="$(security find-certificate -a -Z -p | awk -v h="$APP_HASH" '
  /^SHA-1 hash:/ { keep = ($3 == h) } keep' | openssl x509 -noout -serial | sed 's/^serial=//')"
ok "Signing identities found (distribution certificate serial $APP_SERIAL)"

WORK="$(mktemp -d)"; chmod 700 "$WORK"
cleanup() {
  security delete-keychain "$WORK/filter.keychain-db" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- Provisioning profile through the App Store Connect API -----------------
say "Looking up the Mac App Store profile…"
cat > "$WORK/profile.rb" <<'RUBY'
require "openssl"; require "json"; require "net/http"; require "base64"
key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_FILE")))
b64 = ->(s) { Base64.urlsafe_encode64(s, padding: false) }
now = Time.now.to_i
input = [b64.(JSON.generate(alg: "ES256", kid: ENV["ASC_KEY_ID"], typ: "JWT")),
         b64.(JSON.generate(iss: ENV["ASC_ISSUER_ID"], iat: now, exp: now + 1200, aud: "appstoreconnect-v1"))].join(".")
der = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(input))
sig = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\0")[-32..-1] }.join
TOKEN = "#{input}.#{b64.(sig)}"

def api(method, path, body = nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
  req["Authorization"] = "Bearer #{TOKEN}"
  if body then req["Content-Type"] = "application/json"; req.body = JSON.generate(body) end
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  data = JSON.parse(res.body) rescue {}
  unless res.is_a?(Net::HTTPSuccess)
    detail = (data["errors"] || []).map { |e| e["detail"] || e["title"] }.join("; ")
    abort "App Store Connect #{res.code} on #{path}: #{detail}"
  end
  data
end

bundle = ENV.fetch("BUNDLE_ID")
b = api(:get, "/v1/bundleIds?filter[identifier]=#{bundle}&limit=200")["data"]
      .find { |d| d["attributes"]["identifier"] == bundle } or
  abort "Bundle ID #{bundle} isn't registered on this team (developer.apple.com → Identifiers)"

serial = ENV.fetch("APP_SERIAL").sub(/\A0+/, "").upcase
cert = api(:get, "/v1/certificates?filter[certificateType]=DISTRIBUTION,MAC_APP_DISTRIBUTION&limit=200")["data"]
         .find { |c| c["attributes"]["serialNumber"].to_s.sub(/\A0+/, "").upcase == serial } or
  abort "The keychain's distribution certificate (serial #{serial}) isn't on this team's API key"

profiles = api(:get, "/v1/bundleIds/#{b["id"]}/profiles?limit=200")["data"]
profile = profiles.find do |p|
  a = p["attributes"]
  a["profileType"] == "MAC_APP_STORE" && a["profileState"] == "ACTIVE" &&
    api(:get, "/v1/profiles/#{p["id"]}/certificates?limit=200")["data"].any? { |c| c["id"] == cert["id"] }
end

if profile
  STDERR.puts "✓ Using profile \"#{profile["attributes"]["name"]}\" (expires #{profile["attributes"]["expirationDate"]})"
elsif ENV["DRY_RUN"] == "1"
  STDERR.puts "→ No active Mac App Store profile for this certificate; a real run creates one"
  exit 0
else
  name = "#{bundle} Mac App Store #{Time.now.strftime("%Y-%m-%d %H%M")}"
  profile = api(:post, "/v1/profiles", data: {
    type: "profiles",
    attributes: { name: name, profileType: "MAC_APP_STORE" },
    relationships: { bundleId: { data: { type: "bundleIds", id: b["id"] } },
                     certificates: { data: [{ type: "certificates", id: cert["id"] }] } } })["data"]
  STDERR.puts "✓ Created profile \"#{name}\""
end
File.write(ENV.fetch("OUT"), profile["attributes"]["profileContent"])
RUBY
ASC_KEY_FILE="$ASC_KEY_FILE" ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" \
  BUNDLE_ID="$BUNDLE_ID" APP_SERIAL="$APP_SERIAL" DRY_RUN="$DRY_RUN" OUT="$WORK/profile.b64" \
  /usr/bin/ruby "$WORK/profile.rb"

# --- Export only the two identities ----------------------------------------
if [ "$DRY_RUN" = 1 ]; then
  ok "Dry run: everything checks out. Nothing was exported or set."
  exit 0
fi

say "Exporting the two signing identities (allow each keychain prompt)…"
TMP_PW="$(uuidgen)"; P12_PW="$(openssl rand -base64 24 | tr -d '/+=' )"
security export -k login.keychain-db -t identities -f pkcs12 -P "$TMP_PW" -o "$WORK/all.p12"
security create-keychain -p "$TMP_PW" "$WORK/filter.keychain-db"
security unlock-keychain -p "$TMP_PW" "$WORK/filter.keychain-db"
security import "$WORK/all.p12" -k "$WORK/filter.keychain-db" -P "$TMP_PW" -A >/dev/null
rm -f "$WORK/all.p12"
for h in $(security find-identity "$WORK/filter.keychain-db" | awk '/^ *[0-9]+\)/ {print $2}' | sort -u); do
  [ "$h" = "$APP_HASH" ] || [ "$h" = "$INST_HASH" ] || security delete-identity -Z "$h" "$WORK/filter.keychain-db" >/dev/null
done
security export -k "$WORK/filter.keychain-db" -t identities -f pkcs12 -P "$P12_PW" -o "$WORK/mas.p12"
n="$(security find-identity "$WORK/filter.keychain-db" | awk '/^ *[0-9]+\)/ {print $2}' | sort -u | wc -l | tr -d ' ')"
[ "$n" = 2 ] || die "Expected exactly 2 identities in the export, got $n"
ok "Exported Apple Distribution + installer identities"

# --- Secrets ---------------------------------------------------------------
put() {  # put NAME < value
  gh secret set "$1" --repo "$REPO" >/dev/null && ok "Set $1"
}
base64 -i "$WORK/mas.p12" | tr -d '\n' | put MAS_CERTIFICATE_P12
printf '%s' "$P12_PW"             | put MAS_CERTIFICATE_PASSWORD
tr -d '\n' < "$WORK/profile.b64"  | put MAS_PROVISIONING_PROFILE
base64 -i "$ASC_KEY_FILE" | tr -d '\n' | put APP_STORE_CONNECT_API_KEY
printf '%s' "$ASC_KEY_ID"         | put APP_STORE_CONNECT_API_KEY_ID
printf '%s' "$ASC_ISSUER_ID"      | put APP_STORE_CONNECT_ISSUER_ID

[ -n "${APP_REVIEW_PHONE:-}" ] || read -r -p "App Review phone (blank keeps the current secret): " APP_REVIEW_PHONE </dev/tty
if [ -n "$APP_REVIEW_PHONE" ]; then printf '%s' "$APP_REVIEW_PHONE" | put APP_REVIEW_PHONE
else say "APP_REVIEW_PHONE left as it was"; fi

echo
gh secret list --repo "$REPO"
ok "Done. Push a v* tag to release to the Mac App Store."
