"""Fast CLI launcher.

The full `main.py` imports PySide6 at module load (~250 ms) so the GUI can
load.  That cost was paid even for trivial CLI invocations such as
`--list`, `--version`, `--logs`.  This script is a stripped-down launcher
that re-uses the same `cli_main` logic but never touches PySide6.

For full GUI use, run `python main.py` (or `python main.py --no-gui
--backup ...`).  Detected automations (e.g. scheduled tasks) can keep
calling `python main.py --list` and notice the gain; this `cli.py` is
useful as a drop-in for places that want the speed.
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

# Critical: keep PySide6 OUT of this module.  All the core engines use only
# stdlib + Windows API access; we don't need Qt here.
from core.detection import BrowserDetection
from core.backup import BackupEngine
from core.restore import RestoreEngine
from core.config_manager import config
from core.logger import get_logger, get_log_path

log = get_logger()
log_path = get_log_path()


def parse_cli_args():
    p = argparse.ArgumentParser(description="Universal Browser Backup (CLI)", add_help=True)
    p.add_argument("--list", action="store_true", help="List installed browsers and exit")
    p.add_argument("--backup", action="store_true", help="Run a backup from CLI")
    p.add_argument("--restore", action="store_true", help="Run a restore from CLI")
    p.add_argument("--verify", action="store_true", help="Verify a backup from CLI")
    p.add_argument("--browser", type=str, default="", help="Browser name filter")
    p.add_argument("--profile", type=str, default="Default", help="Profile name")
    p.add_argument("--destination", type=str, default="", help="Destination folder")
    p.add_argument("--source", type=str, default="", help="Backup source folder")
    p.add_argument("--all-profiles", action="store_true", help="Backup every profile")
    p.add_argument("--exclude-cache", action="store_true", help="Skip cache folders")
    p.add_argument("--force", action="store_true", help="Force kill browser process")
    p.add_argument("--logs", action="store_true", help="Show log file path and exit")
    p.add_argument("--version", action="store_true", help="Print version and exit")
    return p.parse_args()


def cli_main(args):
    if args.version:
        print("Universal Browser Backup v2.1.1")
        return 0
    if args.logs:
        print(f"Log file: {get_log_path()}")
        return 0
    if args.list:
        browsers = BrowserDetection.get_installed_browsers()
        if not browsers:
            print("No browsers found.")
            return 0
        print("Installed Browsers:")
        print("-" * 70)
        for b in browsers:
            print(f"  {b['name']} (v{b['version']}) - {b.get('type', '?')}")
            try:
                profiles = BrowserDetection.get_browser_profiles(b)
                for p in profiles:
                    default = " (default)" if p.get("is_default") else ""
                    name_part = p['name']
                    if p.get("display_name") and p["display_name"] != p["name"]:
                        name_part += f" - {p['display_name']}"
                    if p.get("email"):
                        name_part += f" <{p['email']}>"
                    print(f"      - {name_part} [{p['size_mb']:.1f} MB]{default}")
            except Exception as e:
                print(f"      [profiles unavailable: {e}]")
            print()
        return 0

    if args.backup:
        if not args.destination:
            print("ERROR: --destination is required for --backup", file=sys.stderr)
            return 3
        browsers = BrowserDetection.get_installed_browsers()
        if not browsers:
            print("ERROR: no browsers detected", file=sys.stderr)
            return 3
        if args.browser:
            browser = next((b for b in browsers if args.browser.lower() in b["name"].lower()), None)
        else:
            browser = browsers[0]
        if not browser:
            print(f"ERROR: browser '{args.browser}' not found", file=sys.stderr)
            return 3
        os.makedirs(args.destination, exist_ok=True)
        exclude_dirs = config.get_default("excludeFromBackup") if args.exclude_cache else []
        if args.all_profiles:
            profiles = BrowserDetection.get_browser_profiles(browser)
        else:
            profiles = [{"name": args.profile, "size_mb": 0, "is_default": True, "path": ""}]
        results = []
        for p in profiles:
            r = BackupEngine.run_backup(
                browser=browser,
                profile=p,
                destination=args.destination,
                exclude_dirs=exclude_dirs,
                log_file=log_path,
                force=args.force,
                profile_name=p["name"],
            )
            print(f"  {p['name']}: {'OK' if r.get('success') else r.get('message', 'failed')}")
            results.append(r.get("success", False))
        return 0 if all(results) else 5

    if args.restore:
        if not args.source:
            print("ERROR: --source is required for --restore", file=sys.stderr)
            return 3
        browsers = BrowserDetection.get_installed_browsers()
        if not browsers:
            print("ERROR: no browsers detected", file=sys.stderr)
            return 3
        if args.browser:
            browser = next((b for b in browsers if args.browser.lower() in b["name"].lower()), None)
        else:
            browser = browsers[0]
        if not browser:
            print(f"ERROR: browser '{args.browser}' not found", file=sys.stderr)
            return 3
        profiles = BrowserDetection.get_browser_profiles(browser)
        profile = next((p for p in profiles if p["name"] == args.profile), profiles[0] if profiles else None)
        if not profile:
            print("ERROR: no profile found", file=sys.stderr)
            return 3
        r = RestoreEngine.run_restore(
            browser=browser,
            profile=profile,
            backup_path=args.source,
            log_file=log_path,
            force=args.force,
        )
        print(r.get("message", "done"))
        return 0 if r.get("success") else 5

    if args.verify:
        if not args.source:
            print("ERROR: --source is required for --verify", file=sys.stderr)
            return 3
        r = BackupEngine.verify_backup(backup_path=args.source, log_file=log_path)
        print(r.get("message", "done"))
        return 0 if r.get("success") else 5

    return None


def main():
    args = parse_cli_args()
    rc = cli_main(args)
    if rc is not None:
        sys.exit(rc)
    # No CLI flag matched; defer to the heavy GUI launcher.
    import main  # deferred import keeps fast CLI out of PySide6 startup
    main.main()


if __name__ == "__main__":
    main()
