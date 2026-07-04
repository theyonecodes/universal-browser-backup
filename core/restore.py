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
        if not manifest_path.exists():
            return {"valid": False, "message": "No manifest.json found in backup"}

        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)

            # Type Check
            if manifest["browser"]["type"] != browser["type"]:
                return {"valid": False, "message": f"Type mismatch: expected {browser['type']}, found {manifest['browser']['type']}"}

            # Checksum Check
            issues = []
            for file, expected_hash in manifest.get("checksums", {}).items():
                f_path = Path(backup_path) / file
                if not f_path.exists():
                    issues.append(f"Missing critical file: {file}")
                elif expected_hash != "ERROR" and BackupEngine.generate_checksum(str(f_path)) != expected_hash:
                    issues.append(f"Checksum mismatch: {file}")

            if issues:
                return {"valid": False, "message": "; ".join(issues)}

            return {"valid": True, "manifest": manifest}
        except Exception as e:
            return {"valid": False, "message": f"Verification error: {e}"}

    @classmethod
    def run_restore(cls, browser, profile, backup_path, log_file=None, force=False, create_rollback=True):
        # 1. Verify
        verification = cls.verify_backup(backup_path, browser)
        if not verification["valid"]:
            return {"success": False, "message": verification["message"]}

        # 2. Check if running
        process_name = browser["process_name"]
        is_running = False
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
        rollback_path = profile_path.with_name(f"{profile_path.name}.backup_{timestamp}")

        try:
            log.info(f"Creating rollback point: {rollback_path}")
            rollback_path.mkdir(parents=True, exist_ok=True)
            # Use robocopy for fast copy
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
                # Rollback
                log.error(f"Restore failed (code {exit_code}). Rolling back...")
                subprocess.run(
                    ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                    capture_output=True, timeout=300
                )
                return {"success": False, "message": f"Restore failed with code {exit_code}. Rolled back."}

            return {
                "success": True,
                "rollback": str(rollback_path),
                "message": "Restore completed successfully"
            }
        except subprocess.TimeoutExpired:
            # Rollback
            subprocess.run(
                ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                capture_output=True, timeout=300
            )
            return {"success": False, "message": "Restore timed out. Rolled back."}
        except Exception as e:
            # Rollback
            subprocess.run(
                ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                capture_output=True, timeout=300
            )
            return {"success": False, "message": f"Critical error during restore: {e}. Rolled back."}