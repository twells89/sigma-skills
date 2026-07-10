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

Credential resolution: SIGMA_BASE_URL / SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET
must already be in the environment (see the repo README / .env.example).
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request


def _die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def mint_token():
    base = os.environ.get("SIGMA_BASE_URL")
    cid = os.environ.get("SIGMA_CLIENT_ID")
    secret = os.environ.get("SIGMA_CLIENT_SECRET")
    if not base or not cid or not secret:
        _die(
            "FATAL: Sigma credentials not set.\n"
            "  Set SIGMA_BASE_URL / SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET in the\n"
            "  environment (see .env.example / README.md 'Auth' section)."
        )

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


def main():
    ap = argparse.ArgumentParser(description="Mint a Sigma bearer token (shell-neutral).")
    ap.add_argument("--workdir", help="write <WORKDIR>/auth.json (mode 0600)")
    ap.add_argument("--print-export", action="store_true",
                    help="print `export SIGMA_API_TOKEN=...` (bash eval compatibility)")
    ap.add_argument("--print-token", action="store_true",
                    help="print the bare token to stdout")
    args = ap.parse_args()

    base, token = mint_token()

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
