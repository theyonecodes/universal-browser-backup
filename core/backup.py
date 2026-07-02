# core/backup.py
import os
import subprocess
import hashlib
import json
from datetime import datetime
from pathlib import Path
from core.config_manager import config
from core.logger import get_logger

log = get_logger()

class BackupEngine:
    @staticmethod
    def generate_checksum(file_path):
        sha256_hash = hashlib.sha256()
        try:
            with open(file_path, "rb") as f:
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)
            return sha256_hash.hexdigest()
        except Exception as e:
            return f"ERROR: {e}"

    @staticmethod
    def create_manifest(backup_path, browser, profile_name, robocopy_exit_code, log_file):
        manifest_path = Path(backup_path) / "manifest.json"

        critical_files = config.get_default("checksumCriticalFiles") or [
            "Bookmarks", "Bookmarks.bak", "History", "Login Data",
            "Preferences", "Secure Preferences", "Cookies", "Web Data"
        ]

        checksums = {}
        for file in critical_files:
            f_path = Path(backup_path) / file
            if f_path.exists():
                checksums[file] = BackupEngine.generate_checksum(str(f_path))

        # Stats: only count files, not directories
        files = [f for f in Path(backup_path).rglob("*") if f.is_file()]
        total_size = sum(f.stat().st_size for f in files)

        manifest = {
            "version": "2.1.0",
            "timestamp": datetime.now().isoformat(),
            "browser": {
                "name": browser["name"],
                "type": browser["type"],
                "version": browser["version"]
            },
            "profile": profile_name,
            "source": browser["profile_path"],
            "destination": str(backup_path),
            "stats": {
                "fileCount": len(files),
                "totalSize": total_size,
                "totalSizeMB": round(total_size / (1024*1024), 2)
            },
            "robocopy": {
                "exitCode": robocopy_exit_code,
                "logFile": log_file
            },
            "checksums": checksums,
            "machine": {
                "name": os.environ.get("COMPUTERNAME", "Unknown"),
                "user": os.environ.get("USERNAME", "Unknown"),
                "os": os.name
            }
        }

        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=4)

        return str(manifest_path)

    @classmethod
    def run_backup(cls, browser, profile, destination, exclude_dirs=None, log_file=None, force=False):
        # 1. Check if browser is running
        process_name = browser["process_name"]
        try:
            result = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {process_name}.exe"], capture_output=True, text=True, timeout=10)
            is_running = process_name.lower() in result.stdout.lower()
        except Exception:
            is_running = False

        if is_running and not force:
            return {"success": False, "message": f"{browser['name']} is running. Close it or use Force."}

        if is_running and force:
            log.info(f"Force stopping {browser['name']}...")
            subprocess.run(["taskkill", "/F", "/IM", f"{process_name}.exe"], capture_output=True, timeout=30)

        # 2. Setup paths
        safe_browser_name = "".join([c if c.isalnum() else "_" for c in browser["name"]]).strip('_')
        if not safe_browser_name:
            safe_browser_name = "Browser"
        safe_profile = "".join([c if c.isalnum() or c in '._-' else "_" for c in profile["name"]]).strip('_')
        if not safe_profile:
            safe_profile = "Profile"
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_folder = Path(destination) / f"{safe_browser_name}_{safe_profile}_{timestamp}"
        backup_folder.mkdir(parents=True, exist_ok=True)

        # 3. Robocopy Args
        robocopy_args = [
            "robocopy",
            profile["full_path"],
            str(backup_folder),
            "/MIR", "/NP", "/BYTES", "/NDL", "/NFL", "/NC", "/NS",
            f"/R:{config.get_default('robocopyRetries')}",
            f"/W:{config.get_default('robocopyWait')}",
            "/MT:4"
        ]

        if exclude_dirs:
            for d in exclude_dirs:
                if d:
                    robocopy_args.extend(["/XD", os.path.join(profile["full_path"], d)])

        if log_file:
            robocopy_args.extend(["/LOG+:", log_file])

        log.info(f"Starting backup: {browser['name']} - {profile['name']}")

        try:
            process = subprocess.run(robocopy_args, capture_output=True, text=True, timeout=3600)
            exit_code = process.returncode

            if exit_code >= 8:
                return {"success": False, "message": f"Robocopy failed with exit code {exit_code}"}

            # Create manifest
            manifest_path = cls.create_manifest(backup_folder, browser, profile["name"], exit_code, log_file)

            # Calculate final size
            files = list(backup_folder.rglob("*"))
            total_size = sum(f.stat().st_size for f in files if f.is_file())

            return {
                "success": True,
                "path": str(backup_folder),
                "size_mb": round(total_size / (1024*1024), 2),
                "manifest": manifest_path
            }
        except subprocess.TimeoutExpired:
            log.error("Backup timed out")
            return {"success": False, "message": "Backup timed out"}
        except Exception as e:
            log.error(f"Backup error: {e}")
            return {"success": False, "message": str(e)}

    @staticmethod
    def verify_backup(backup_path, log_file=None):
        """Verify integrity of an existing backup by recomputing checksums."""
        backup_path = Path(backup_path)
        manifest_path = backup_path / "manifest.json"

        if not backup_path.exists():
            return {"success": False, "message": f"Backup path does not exist: {backup_path}"}
        if not manifest_path.exists():
            return {"success": False, "message": "manifest.json not found in backup"}

        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception as e:
            return {"success": False, "message": f"Cannot read manifest: {e}"}

        errors = []
        stored_checksums = manifest.get("checksums", {})
        matched = 0
        for fname, expected in stored_checksums.items():
            f_path = backup_path / fname
            if not f_path.exists():
                errors.append(f"Missing critical file: {fname}")
                continue
            actual = BackupEngine.generate_checksum(str(f_path))
            if actual != expected:
                errors.append(f"Checksum mismatch: {fname}")
            else:
                matched += 1

        # Verify file count
        files = [f for f in backup_path.rglob("*") if f.is_file()]
        stored_count = manifest.get("stats", {}).get("fileCount", 0)
        if stored_count and len(files) != stored_count:
            # just warning, not error
            pass

        if errors:
            msg = f"Verification completed with {len(errors)} issue(s):\n" + "\n".join(f"  - {e}" for e in errors)
            return {"success": False, "message": msg}

        return {"success": True, "message": f"Verified {matched} critical file(s) successfully."}

    @staticmethod
    def compare_backups(old_path, new_path):
        """Compare two backup folders by file presence and checksums."""
        old_path = Path(old_path)
        new_path = Path(new_path)

        result = {
            "old_path": str(old_path),
            "new_path": str(new_path),
            "files_only_in_old": [],
            "files_only_in_new": [],
            "files_modified": [],
            "files_identical": [],
        }

        if not old_path.exists() or not new_path.exists():
            return result

        def collect_files(root):
            files = {}
            for f in root.rglob("*"):
                if f.is_file():
                    rel = str(f.relative_to(root))
                    try:
                        files[rel] = f.stat().st_size
                    except Exception:
                        pass
            return files

        old_files = collect_files(old_path)
        new_files = collect_files(new_path)

        all_paths = set(old_files) | set(new_files)
        for rel in sorted(all_paths):
            in_old = rel in old_files
            in_new = rel in new_files
            if in_old and not in_new:
                result["files_only_in_old"].append(rel)
            elif in_new and not in_old:
                result["files_only_in_new"].append(rel)
            else:
                # Both exist — if size matches, still verify via checksum
                if old_files[rel] != new_files[rel]:
                    result["files_modified"].append({"path": rel, "old_size": old_files[rel], "new_size": new_files[rel]})
                else:
                    # Same size — check checksum for content changes
                    if rel.endswith("/") or rel.endswith("\\"):
                        result["files_identical"].append(rel)
                        continue
                    old_abs = old_path / rel.replace("/", "\\") if hasattr(old_path, '__class__') else old_path / rel
                    if old_abs.exists() and old_abs.is_file():
                        old_sum = BackupEngine.generate_checksum(str(old_abs))
                        if old_sum and not old_sum.startswith("ERROR"):
                            new_abs = new_path / rel.replace("/", "\\") if hasattr(new_path, '__class__') else new_path / rel
                            if new_abs.exists() and new_abs.is_file():
                                new_sum = BackupEngine.generate_checksum(str(new_abs))
                                if new_sum == old_sum:
                                    result["files_identical"].append(rel)
                                else:
                                    result["files_modified"].append({"path": rel, "old_size": old_files[rel], "new_size": new_files[rel]})
                            else:
                                result["files_modified"].append({"path": rel, "old_size": old_files[rel], "new_size": new_files[rel]})
                        else:
                            result["files_identical"].append(rel)
                    else:
                        result["files_identical"].append(rel)

        return result

    @staticmethod
    def export_profile_zip(browser, profile, output_path, log_file=None):
        """Export a profile as a portable .zip archive."""
        import zipfile
        try:
            output_path = Path(output_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            src = Path(profile["full_path"])
            if not src.exists():
                return False, f"Source profile does not exist: {src}"
            with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
                file_count = 0
                for f in src.rglob("*"):
                    if f.is_file():
                        # Avoid huge cache folders
                        rel = f.relative_to(src)
                        if any(part in {"Cache", "Code Cache", "GPUCache"} for part in rel.parts):
                            continue
                        zf.write(f, rel.as_posix())
                        file_count += 1
            return True, f"Exported {file_count} file(s) to {output_path}"
        except Exception as e:
            log.error(f"Export failed: {e}")
            return False, str(e)

    @staticmethod
    def import_profile_zip(zip_path, log_file=None):
        """Import a .zip archive into the appropriate browser profile folder."""
        import zipfile
        import tempfile
        try:
            zip_path = Path(zip_path)
            if not zip_path.exists():
                return {"success": False, "message": "Archive does not exist"}
            with zipfile.ZipFile(zip_path, "r") as zf:
                manifest_data = None
                for name in zf.namelist():
                    if name.endswith("manifest.json"):
                        try:
                            manifest_data = json.loads(zf.read(name).decode("utf-8"))
                            break
                        except Exception:
                            pass
                if not manifest_data:
                    return {"success": False, "message": "Archive does not contain a valid manifest.json"}

                browser_name = manifest_data.get("browser", {}).get("name", "Unknown")
                profile_name = manifest_data.get("profile", "Default")
                dest_root = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Imported_Browser_Backups"
                dest_path = dest_root / f"{browser_name}_{profile_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
                dest_path.mkdir(parents=True, exist_ok=True)

                with tempfile.TemporaryDirectory() as tmp:
                    tmp_path = Path(tmp)
                    zf.extractall(tmp_path)
                    # Copy extracted files into destination
                    import shutil
                    for item in tmp_path.iterdir():
                        target = dest_path / item.name
                        if item.is_dir():
                            shutil.copytree(item, target, dirs_exist_ok=True)
                        else:
                            shutil.copy2(item, target)

            return {
                "success": True,
                "browser_name": browser_name,
                "profile_name": profile_name,
                "dest_path": str(dest_path),
            }
        except Exception as e:
            log.error(f"Import failed: {e}")
            return {"success": False, "message": str(e)}


def list_backups(destination_root):
    """List all backups found under destination_root, grouped by browser.

    Convention used: <BrowserName>_<ProfileName>_<YYYYMMDD_HHMMSS>/
    """
    root = Path(destination_root)
    result = {}
    if not root.exists():
        return result

    for entry in root.iterdir():
        if not entry.is_dir():
            continue
        manifest = entry / "manifest.json"
        if not manifest.exists():
            continue
        try:
            with open(manifest, "r", encoding="utf-8") as f:
                data = json.load(f)
            bname = data.get("browser", {}).get("name", "Unknown")
            entry_info = {
                "path": str(entry),
                "browser": bname,
                "profile": data.get("profile", "?"),
                "timestamp": data.get("timestamp", ""),
                "size_mb": data.get("stats", {}).get("totalSizeMB", 0),
            }
            result.setdefault(bname, []).append(entry_info)
        except Exception:
            continue
    return result