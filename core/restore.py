# core/restore.py
import os
import subprocess
import json
import shutil
from pathlib import Path
from datetime import datetime
from core.backup import BackupEngine
from core.logger import log

class RestoreEngine:
    @staticmethod
    def verify_backup(backup_path, browser):
        manifest_path = Path(backup_path) / "manifest.json"
        manifest = None

        if manifest_path.exists():
            try:
                with open(manifest_path, "r", encoding="utf-8") as f:
                    manifest = json.load(f)
            except Exception as e:
                return {"valid": False, "message": f"Cannot read manifest.json: {e}"}

            # Type Check
            if browser and browser.get("type") and manifest.get("browser", {}).get("type") != browser["type"]:
                return {"valid": False, "message": f"Type mismatch: expected {browser['type']}, found {manifest['browser']['type']}"}

            # Checksum Check
            issues = []
            for file, expected_hash in manifest.get("checksums", {}).items():
                f_path = Path(backup_path) / file
                if not f_path.exists():
                    issues.append(f"Missing critical file: {file}")
                elif expected_hash and not expected_hash.startswith("ERROR") and BackupEngine.generate_checksum(str(f_path)) != expected_hash:
                    issues.append(f"Checksum mismatch: {file}")

            if issues:
                return {"valid": False, "message": "; ".join(issues)}

            return {"valid": True, "manifest": manifest}

        # No manifest.json: derive critical-file presence recursively
        # (critical files live in subfolders like \Default\Login Data, \Default\Bookmarks)
        critical_files = [
            "Login Data", "Cookies", "Preferences", "Secure Preferences",
            "Bookmarks", "Bookmarks.bak", "History", "Web Data"
        ]
        backup_root = Path(backup_path)
        if not backup_root.exists():
            return {"valid": False, "message": f"Backup path does not exist: {backup_path}"}

        present_recursive = {}
        for cf in critical_files:
            # Quick scan top-level + 1 level deep
            found = list(backup_root.glob(cf)) + list(backup_root.glob(f"*/{cf}")) + list(backup_root.glob(f"*/*/{cf}"))
            if found:
                present_recursive[cf] = str(found[0])

        # Count presence: must have at least 3 distinct critical files
        unique_present = {os.path.basename(v).lower(): v for v in present_recursive.values()}
        if len(unique_present) < 3:
            return {
                "valid": False,
                "message": f"Backup folder has no manifest and only {len(present_recursive)} known critical file(s) found — too risky to restore."
            }

        return {
            "valid": True,
            "manifest": {
                "version": "legacy",
                "browser": {"name": (browser or {}).get("name", "Unknown") if browser else "Unknown",
                            "type": (browser or {}).get("type", "Unknown") if browser else "Unknown"},
                "profile": "Unknown",
                "checksums": {},
                "_legacy_no_manifest": True,
                "_detected_critical_files": present_recursive,
            }
        }

    @classmethod
    def run_restore(cls, browser, profile, backup_path, log_file=None, force=False, create_rollback=True):
        # 1. Verify
        verification = cls.verify_backup(backup_path, browser)
        if not verification["valid"]:
            return {"success": False, "message": verification["message"]}

        # 2. Check if running
        process_name = browser.get("process_name", "")
        is_running = False
        if process_name:
            try:
                result = subprocess.run(
                    ["tasklist", "/FI", f"IMAGENAME eq {process_name}.exe"],
                    capture_output=True, text=True, timeout=10
                )
                is_running = process_name.lower() in result.stdout.lower()
            except Exception:
                is_running = False

        if is_running:
            if not force:
                return {"success": False, "message": f"{browser['name']} is running. Close it first."}
            else:
                log.info(f"Force stopping {browser['name']}...")
                subprocess.run(["taskkill", "/F", "/IM", f"{process_name}.exe"], capture_output=True, timeout=10)

        # 3. Rollback point
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        profile_path = Path(profile["full_path"])
        rollback_path = None
        profile_existed_before = profile_path.exists()

        if create_rollback and profile_existed_before:
            rollback_path = profile_path.with_name(f"{profile_path.name}.backup_{timestamp}")
            try:
                log.info(f"Creating rollback point: {rollback_path}")
                rollback_path.parent.mkdir(parents=True, exist_ok=True)
                rb_code = subprocess.run(
                    ["robocopy", str(profile_path), str(rollback_path), "/MIR", "/NP", "/R:3", "/W:2"],
                    capture_output=True, timeout=300
                ).returncode
                if rb_code >= 8:
                    log.warning(f"Rollback copy had warnings (exit code {rb_code})")
            except Exception as e:
                return {"success": False, "message": f"Rollback creation failed: {e}"}

        # 4. Restore
        robocopy_args = [
            "robocopy",
            str(backup_path),
            str(profile_path),
            "/MIR", "/NP", "/R:3", "/W:2"
        ]

        if log_file:
            robocopy_args.extend(["/LOG+:", log_file])
        else:
            robocopy_args.append("/LOG:restore_output.txt")

        log.info(f"Restoring {browser['name']} - {profile['name']}...")

        try:
            process = subprocess.run(robocopy_args, capture_output=True, text=True, timeout=3600)
            exit_code = process.returncode

            if exit_code >= 8:
                log.error(f"Restore failed (code {exit_code}). Rolling back...")
                if rollback_path and profile_path.exists():
                    subprocess.run(
                        ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                        capture_output=True, timeout=300
                    )
                return {"success": False, "message": f"Restore failed with code {exit_code}. Rolled back."}

            result = {
                "success": True,
                "rollback": str(rollback_path) if rollback_path else None,
                "message": "Restore completed successfully"
            }
            return result
        except subprocess.TimeoutExpired:
            if rollback_path and profile_path.exists():
                subprocess.run(
                    ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                    capture_output=True, timeout=300
                )
            return {"success": False, "message": "Restore timed out. Rolled back."}
        except Exception as e:
            if rollback_path and profile_path.exists():
                subprocess.run(
                    ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                    capture_output=True, timeout=300
                )
            return {"success": False, "message": f"Critical error during restore: {e}. Rolled back."}
