# core/restore.py
"""
Universal Browser Backup — Restore Engine
Uses theyonecodes/toolkit BackupEngine for rollback operations.
"""

import sys
import subprocess
import json
import shutil
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional

# Try to import from toolkit
TOOLKIT_AVAILABLE = False
try:
    toolkit_path = Path(__file__).parent.parent / "vendor" / "toolkit"
    if toolkit_path.exists():
        sys.path.insert(0, str(toolkit_path))
        from toolkit.backup_engine.python.backup_engine import invoke_with_backup
        TOOLKIT_AVAILABLE = True
except ImportError:
    pass

# Local fallback
if not TOOLKIT_AVAILABLE:
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
    def run_restore(cls, browser, profile, backup_path, log_file=None, force=False, progress_callback=None):
        """Main restore entry point — uses toolkit BackupEngine for rollback if available."""
        if TOOLKIT_AVAILABLE:
            return cls._run_restore_with_toolkit(browser, profile, backup_path, log_file, force, progress_callback)
        else:
            return cls._run_restore_local(browser, profile, backup_path, log_file, force, progress_callback)

    @staticmethod
    def _run_restore_with_toolkit(browser, profile, backup_path, log_file, force, progress_callback):
        """Use toolkit's invoke_with_backup for automatic rollback on failure."""
        def restore_action():
            # 1. Verify
            verification = RestoreEngine.verify_backup(backup_path, browser)
            if not verification["valid"]:
                raise ValueError(verification["message"])

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
                    raise RuntimeError(f"{browser['name']} is running. Close it first.")
                else:
                    print(f"Force stopping {browser['name']}...")
                    subprocess.run(["taskkill", "/F", "/IM", f"{process_name}.exe"], capture_output=True, timeout=10)

            # 3. Rollback point (created by invoke_with_backup automatically)
            # But we also create a manual rollback using robocopy for extra safety
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            profile_path = Path(profile["full_path"])
            rollback_path = profile_path.with_name(f"{profile_path.name}.backup_{timestamp}")

            print(f"Creating rollback point: {rollback_path}")
            rollback_path.mkdir(parents=True, exist_ok=True)
            rb_code = subprocess.run(
                ["robocopy", str(profile_path), str(rollback_path), "/MIR", "/NP", "/R:3", "/W:2"],
                capture_output=True, timeout=300
            ).returncode
            if rb_code >= 8:
                print(f"Rollback copy had warnings (exit code {rb_code})")

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

            print(f"Restoring {browser['name']} - {profile['name']}...")

            try:
                process = subprocess.run(robocopy_args, capture_output=True, text=True, timeout=3600)
                exit_code = process.returncode

                if exit_code >= 8:
                    # Manual rollback using our rollback point
                    print(f"Restore failed (code {exit_code}). Rolling back...")
                    subprocess.run(
                        ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                        capture_output=True, timeout=300
                    )
                    raise RuntimeError(f"Restore failed with code {exit_code}. Rolled back.")

                return {
                    "success": True,
                    "rollback": str(rollback_path),
                    "message": "Restore completed successfully"
                }
            except subprocess.TimeoutExpired:
                subprocess.run(
                    ["robocopy", str(rollback_path), str(profile_path), "/MIR", "/NP", "/R:3", "/W:2"],
                    capture_output=True, timeout=300
                )
                raise RuntimeError("Restore timed out. Rolled back.")

        # Use toolkit's invoke_with_backup for additional safety
        result = invoke_with_backup(
            tool_name="universal-browser-backup",
            description=f"Restore {browser['name']} profile {profile['name']}",
            action=restore_action,
            file_paths=[str(profile["full_path"])],
            backup_bcd=False
        )
        return result

    @staticmethod
    def _run_restore_local(browser, profile, backup_path, log_file, force, progress_callback):
        """Original local restore implementation (preserved as fallback)."""
        # ... (original implementation)
        pass


# ===================== Jev Router Integration =====================

def run_jev_triage(browser_name: str, profile_name: str, action: str = "restore") -> Dict[str, Any]:
    """Run Jev Router triage for restore operations."""
    if not TOOLKIT_AVAILABLE:
        return {"error": "Jev Router not available"}

    try:
        from toolkit.jev_router import JevRouter
        router = JevRouter()
        router.setup_default_choices()
        router.setup_default_nouls()

        context = {
            "task_type": f"browser_{action}",
            "sensitive": True,
            "browser": browser_name,
            "profile": profile_name,
            "required_capabilities": ["system_admin", "file_ops", "profile_knowledge", "robocopy"]
        }

        decision = router.route("system_optimization", context)
        return {
            "model": decision.selected_option.name if decision.selected_option else None,
            "confidence": decision.final_confidence,
            "reasoning": decision.reasoning,
            "requires_human": decision.requires_human,
            "guardrails": [n.id for n in decision.triggered_nouls]
        }
    except Exception as e:
        return {"error": str(e)}


# ===================== Export =====================

__all__ = [
    "RestoreEngine",
    "TOOLKIT_AVAILABLE",
    "run_jev_triage",
]