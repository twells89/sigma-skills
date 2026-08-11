#!/usr/bin/env python3
"""get_token.py — shell-neutral Sigma token minting (Python stdlib only).

get-token.sh only works in bash/zsh (`eval "$(get-token.sh)"`) — that idiom
doesn't run in PowerShell or cmd.exe. This script is the cross-shell twin:
instead of printing an `export` line, it writes the token to
<WORKDIR>/auth.json so every shell — bash, PowerShell, cmd, or an agent
driving any of them — uses the exact same invocation:

    python3 scripts/get_token.py --workdir <WORKDIR>   # writes <WORKDIR>/auth.json (0600)
    python3 scripts/get_token.py --print-export         # bash: eval "$(...)" compatibility
    python3 scripts/get_token.py --print-token          # bare token to stdout (for scripting)

auth.json shape:  {"SIGMA_API_TOKEN": "...", "SIGMA_BASE_URL": "..."}
It is read by scripts/lib/sigma_rest.rb (env vars still win) and MUST be
kept out of version control — it holds a live bearer token.

Credential resolution (SIGMA_BASE_URL is always required):
  1. Client credentials — if SIGMA_CLIENT_ID and SIGMA_CLIENT_SECRET are in
     the environment, exchange them for a token (headless, the default).
  2. Browser login — otherwise, if you have signed in once via the sigma-api
     skill's browser login (`browser-login.sh`), this redeems the refresh
     token it stored in your OS keychain — no browser round-trip, no client
     ID/secret. It serves a still-valid cached access token when present and
     only redeems (and rotates) the refresh token when the cache is stale.
See the repo README / .env.example for setup.
"""

import argparse
import base64
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Pin every OAuth host to a known Sigma cloud. auth.json is not eval'd, but the
# token still becomes an Authorization header, so never POST a keychain-stored
# refresh token to a host a tampered keychain value might name.
SIGMA_DOMAIN = "sigma" "computing.com"
# RFC 6750 bearer-token alphabet — reject anything outside it before use.
_BEARER_RE = re.compile(r"^[A-Za-z0-9._~+/=-]+$")


def _die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def _assert_sigma_host(url):
    # Parse the authority exactly as a client would: strip scheme, stop at the
    # first '/', '?', or '#', drop any userinfo and port. A naive parse would
    # let a fragment spoof the trusted suffix.
    host = re.sub(r"^https?://", "", url)
    host = re.split(r"[/?#]", host, 1)[0]
    host = host.split("@")[-1]
    host = re.sub(r":\d+$", "", host)
    if not (host == SIGMA_DOMAIN or host.endswith("." + SIGMA_DOMAIN)):
        _die(f"FATAL: refusing OAuth endpoint on non-Sigma host: {host or '<none>'}")


def _mint_client_credentials(base, cid, secret):
    # The #1 hard blocker in practice: a settings file where
    # SIGMA_CLIENT_SECRET is a COPY of SIGMA_CLIENT_ID. Sigma returns the
    # opaque "client secret provided is invalid" and nothing else runs.
    # Catch that obvious paste-error here with an actionable message.
    if secret == cid:
        _die(
            "FATAL: SIGMA_CLIENT_SECRET is identical to SIGMA_CLIENT_ID — you pasted the\n"
            "client ID into both fields. The secret is a SEPARATE, longer value shown only\n"
            "once when the API key was created. Fix it and re-run."
        )

    creds = base64.b64encode(f"{cid}:{secret}".encode()).decode()
    req = urllib.request.Request(
        f"{base}/v2/auth/token",
        data=b"grant_type=client_credentials",
        headers={
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        _die(
            "Token exchange failed — check SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET\n"
            f"  base : {base}\n"
            f"  id   : {len(cid)} chars   secret: {len(secret)} chars\n"
            "  (a valid Sigma secret is ~128 chars — if the secret is the same length as\n"
            f"   the id, you likely pasted the id into both fields.)\n"
            f"  server -> {e.code} {e.reason}"
        )
    except urllib.error.URLError as e:
        _die(f"Token exchange failed — could not reach {base}: {e.reason}")

    token = payload.get("access_token")
    if not token:
        _die("Token exchange failed — response did not contain access_token")
    return base, token


# --- Browser-login fallback: redeem the refresh token that sigma-api's
# --- browser-login.sh stored in the OS keychain. Mirrors refresh-token.sh:
# --- serve a valid cached access token, else redeem (and rotate) the refresh
# --- token. Naming matches what browser-login.sh writes (macOS service
# --- "sigma-api:<name>"; libsecret service=sigma-api key=<name>). ---
def _keychain_backend():
    if shutil.which("security"):
        return "macos"
    if shutil.which("secret-tool"):
        return "libsecret"
    return None


def _kc_get(backend, name):
    try:
        if backend == "macos":
            out = subprocess.run(
                ["security", "find-generic-password", "-a", getpass.getuser(),
                 "-s", f"sigma-api:{name}", "-w"],
                capture_output=True, text=True,
            )
        else:
            out = subprocess.run(
                ["secret-tool", "lookup", "service", "sigma-api", "key", name],
                capture_output=True, text=True,
            )
    except OSError:
        return ""
    if out.returncode != 0:
        return ""
    return out.stdout.strip()


def _kc_set(backend, name, value):
    try:
        if backend == "macos":
            subprocess.run(
                ["security", "add-generic-password", "-U", "-a", getpass.getuser(),
                 "-s", f"sigma-api:{name}", "-w", value],
                capture_output=True, text=True,
            )
        else:
            subprocess.run(
                ["secret-tool", "store", "--label", f"sigma-api {name}",
                 "service", "sigma-api", "key", name],
                input=value, capture_output=True, text=True,
            )
    except OSError:
        pass


def _mint_browser_refresh(base):
    """Return (base, token) from a stored browser-login refresh token, or None
    when there is nothing stored to redeem (so the caller can report a single
    unified 'no credentials' error)."""
    backend = _keychain_backend()
    if backend is None:
        return None
    refresh = _kc_get(backend, "refresh-token")
    if not refresh:
        return None

    now = int(time.time())
    cached = _kc_get(backend, "access-token")
    expiry = _kc_get(backend, "access-expiry")
    if cached and expiry.isdigit() and int(expiry) > now:
        return base, cached

    client_id = _kc_get(backend, "client-id")
    token_url = _kc_get(backend, "token-url")
    if not client_id or not token_url:
        _die(
            "FATAL: found a stored browser-login refresh token but not the client-id /\n"
            "  token-url needed to redeem it (browser-login.sh persists these on macOS).\n"
            "  Re-run the sigma-api skill's browser-login.sh, or use client credentials."
        )
    _assert_sigma_host(token_url)

    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh,
        "client_id": client_id,
    }).encode()
    req = urllib.request.Request(
        token_url,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as e:
        _die(
            "Refresh failed — the saved refresh token may be revoked or expired.\n"
            "  Re-run the sigma-api skill's browser-login.sh to sign in again.\n"
            f"  server -> {e.code} {e.reason}"
        )
    except urllib.error.URLError as e:
        _die(f"Refresh failed — could not reach {token_url}: {e.reason}")

    token = payload.get("access_token")
    if not token:
        _die("Refresh failed — response did not contain access_token")

    try:
        expires_in = int(payload.get("expires_in") or 3600)
    except (TypeError, ValueError):
        expires_in = 3600
    # 60s safety margin so a token never expires mid-request.
    _kc_set(backend, "access-token", token)
    _kc_set(backend, "access-expiry", str(now + expires_in - 60))
    # Refresh tokens are single-use and rotate — persist any replacement or the
    # next redemption fails.
    new_refresh = payload.get("refresh_token")
    if new_refresh and new_refresh != refresh:
        _kc_set(backend, "refresh-token", new_refresh)
    return base, token


def mint_token():
    base = os.environ.get("SIGMA_BASE_URL")
    if not base:
        _die(
            "FATAL: SIGMA_BASE_URL not set.\n"
            "  Set it to your cloud's API host (see .env.example / README.md 'Auth')."
        )

    cid = os.environ.get("SIGMA_CLIENT_ID")
    secret = os.environ.get("SIGMA_CLIENT_SECRET")
    if cid and secret:
        return _mint_client_credentials(base, cid, secret)

    # No client credentials — fall back to a browser-login refresh token, if one
    # was stored by the sigma-api skill's browser-login.sh.
    result = _mint_browser_refresh(base)
    if result:
        return result

    _die(
        "FATAL: no Sigma credentials available.\n"
        "  Choose one of two auth options:\n"
        "    - Client credentials: set SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET (headless).\n"
        "    - Browser login: sign in once via the sigma-api skill, then retry —\n"
        "        eval \"$(bash <repo-root>/sigma-api/scripts/browser-login.sh)\"\n"
        "      It stores a refresh token in your OS keychain that this script\n"
        "      redeems headlessly. SIGMA_BASE_URL must still be set either way.\n"
        "  See .env.example / README.md 'Auth' section."
    )


def main():
    ap = argparse.ArgumentParser(description="Mint a Sigma bearer token (shell-neutral).")
    ap.add_argument("--workdir", help="write <WORKDIR>/auth.json (mode 0600)")
    ap.add_argument("--print-export", action="store_true",
                    help="print `export SIGMA_API_TOKEN=...` (bash eval compatibility)")
    ap.add_argument("--print-token", action="store_true",
                    help="print the bare token to stdout")
    args = ap.parse_args()

    base, token = mint_token()

    if not _BEARER_RE.match(token):
        _die("FATAL: token contains unexpected characters; refusing to emit.")

    wrote = False
    if args.workdir:
        os.makedirs(args.workdir, exist_ok=True)
        auth_path = os.path.join(args.workdir, "auth.json")
        # Write 0600 atomically-ish: create with restrictive mode from the start.
        fd = os.open(auth_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"SIGMA_API_TOKEN": token, "SIGMA_BASE_URL": base}, fh)
        try:
            os.chmod(auth_path, 0o600)  # no-op on Windows, harmless
        except OSError:
            pass
        print(f"wrote {auth_path} (Sigma token; expires ~1h)", file=sys.stderr)
        wrote = True

    if args.print_export:
        print(f"export SIGMA_API_TOKEN={token}")
    elif args.print_token:
        print(token)
    elif not wrote:
        # Default with no flags: behave like get-token.sh so `eval "$(...)"`
        # keeps working in bash and nobody's muscle memory breaks.
        print(f"export SIGMA_API_TOKEN={token}")


if __name__ == "__main__":
    main()
