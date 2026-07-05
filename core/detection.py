# core/detection.py
import os
import re
import json
import subprocess
import time
from functools import lru_cache
from pathlib import Path
from core.config_manager import config
from core.logger import log

# Cache dir size lookups for 30 seconds so refresh clicks don't re-walk the
# disk.  Reading a 2 GB Chrome profile tree 7 times in a row was the single
# biggest GUI-thread freeze.
_SIZE_CACHE_TTL = 30.0  # seconds
_SIZE_CACHE_LIMIT = 256  # entries
_SIZE_CACHE = {}


def _size_cache_get(path):
    rec = _SIZE_CACHE.get(path)
    if not rec:
        return None
    if time.monotonic() - rec[1] > _SIZE_CACHE_TTL:
        return None
    return rec[0]


def _size_cache_set(path, size):
    if len(_SIZE_CACHE) >= _SIZE_CACHE_LIMIT:
        # Drop an arbitrary oldest entry.
        try:
            oldest = next(iter(_SIZE_CACHE))
            _SIZE_CACHE.pop(oldest, None)
        except StopIteration:
            pass
    _SIZE_CACHE[path] = (size, time.monotonic())


# Chrome / Edge / most Chromium browsers ship with cache subdirs that contain
# the bulk of disk usage but aren't worth backing up.  When estimating a
# profile size in MB for display we treat these as "configurable exclusion" so
# the GUI doesn't have to walk hundreds of megabytes of cache files just to
# display "Profile 1 - 1.3 GB".
_FAST_EXCLUDE_DIRS = {
    "Cache", "Code Cache", "GPUCache", "Service Worker", "URLBlocklist",
    "storage", "File System", "IndexedDB-backups", "ShaderCache",
    "GraphiteDawnCache", "GrShaderCache", "Cache_Data",
}


def _quick_size(path):
    """Cheap upper-bound estimate: top-level file sizes + one-shot walk.

    Walks the tree ONCE but uses os.scandir (which avoids stat() on directory
    entries when only is_file is needed) and skips known heavy dirnames.
    For a 1 GB Chrome profile with 2 GB of cache this returns a useful
    MB number in ~50-100 ms instead of ~600 ms.

    For an *exact* number the GUI/backend use the full walker below.  This
    one is for display only.
    """
    total = 0
    try:
        entries = list(os.scandir(path))
    except Exception:
        return 0
    for entry in entries:
        try:
            if entry.is_file(follow_symlinks=False):
                total += entry.stat().st_size
            elif entry.is_dir(follow_symlinks=False):
                name = entry.name
                if name in _FAST_EXCLUDE_DIRS:
                    continue  # known heavy cache dir
                total += _quick_size(entry.path)
        except Exception:
            continue
    return total


def _full_size(path):
    """Exact recursive size walker for BackupEngine use, where precision matters."""
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_file(follow_symlinks=False):
                        total += entry.stat().st_size
                    elif entry.is_dir(follow_symlinks=False):
                        total += _full_size(entry.path)
                except Exception:
                    continue
    except Exception:
        pass
    return total


class BrowserDetection:
    @staticmethod
    def get_chromium_browsers():
        browsers = []
        local_appdata = os.environ.get("LOCALAPPDATA", "")
        program_files = os.environ.get("ProgramFiles", "")
        program_files_x86 = os.environ.get("ProgramFiles(x86)", "")

        browser_list = config.get("browsers", [])
        chromium_browsers = [b for b in browser_list if b.get("type") == "Chromium"]

        for browser_def in chromium_browsers:
            local_path = browser_def.get("localPath", "")
            if not local_path:
                continue

            base_path = Path(local_appdata) / local_path
            if not base_path.exists():
                continue

            user_data_path = None
            profile_root = browser_def.get("profileRoot", "Default")

            # Check base_path itself first — most Chromium browsers' localPath
            # already ends in "User Data", so base_path IS the data folder.
            if (base_path / "Local State").exists():
                user_data_path = base_path
            else:
                for variant in (f"{profile_root}", "Default", "User Data", "User Data V2", f"{profile_root} V2"):
                    candidate = base_path / variant
                    if candidate.exists() and candidate.is_dir():
                        user_data_path = candidate
                        break

            if not user_data_path:
                continue

            if not (user_data_path / "Local State").exists():
                continue

            browser_name = browser_def.get("name", local_path.split('\\')[-1])
            alias = browser_def.get("alias", browser_name)
            process_name = browser_def.get("processName", alias.lower().replace(" ", ""))

            exe_path = None
            program_files_path = browser_def.get("programFilesPath")
            if program_files_path:
                for pf in (program_files, program_files_x86):
                    if not pf:
                        continue
                    exe_dir = Path(pf) / program_files_path / "Application"
                    if exe_dir.exists():
                        for file in exe_dir.glob("*.exe"):
                            name_lower = file.name.lower()
                            if not any(x in name_lower for x in ["uninstall", "setup", "installer", "update", "helper", "crashpad"]):
                                exe_path = str(file)
                                break
                        if exe_path:
                            break

            version = "Unknown"
            if exe_path:
                version = BrowserDetection._get_file_version(exe_path)

            browsers.append({
                "name": f"{alias} ({browser_def.get('engineFamily', 'Chromium')})",
                "type": browser_def.get("type", "Chromium"),
                "engineFamily": browser_def.get("engineFamily", "Chromium"),
                "profile_path": str(user_data_path),
                "exe_path": exe_path,
                "process_name": process_name,
                "version": version,
                "raw_name": alias,
                "icon": browser_def.get("icon", alias.lower()),
                "detectStrategy": browser_def.get("detectStrategy", "localState")
            })

        return browsers

    @staticmethod
    def get_gecko_browsers():
        browsers = []
        browser_list = config.get("browsers", [])
        gecko_browsers = [b for b in browser_list if b.get("type") == "Gecko"]

        appdata = os.environ.get("APPDATA", "")
        local_appdata = os.environ.get("LOCALAPPDATA", "")

        for browser_def in gecko_browsers:
            local_path = browser_def.get("localPath", "")
            if not local_path:
                continue

            detect_strategy = browser_def.get("detectStrategy", "profilesIni")
            profile_path = None

            if detect_strategy == "localProfilesDir":
                # Zen-style: profiles live in LOCALAPPDATA\{localPath}\Profiles\
                # Each dir is named <hash>.<profile_name>
                local_root = Path(local_appdata) / local_path
                profiles_dir = local_root / "Profiles"
                if profiles_dir.exists() and profiles_dir.is_dir():
                    profile_path = str(local_root)
                else:
                    continue
            else:
                # Standard Firefox-style: profiles.ini in APPDATA
                firefox_root = Path(appdata) / local_path
                profiles_ini = firefox_root / "profiles.ini"

                if not profiles_ini.exists():
                    continue

                try:
                    content = profiles_ini.read_text(encoding='utf-8', errors='ignore')
                    has_profiles = any(line.strip().startswith('Path=') for line in content.splitlines())
                    if not has_profiles:
                        continue
                except Exception as e:
                    log.error(f"Error reading Firefox profiles.ini: {e}")
                    continue

                profile_path = str(firefox_root)

            alias = browser_def.get("alias", browser_def.get("name", "Firefox"))
            process_name = browser_def.get("processName", "firefox")

            exe_path = None
            program_files_path = browser_def.get("programFilesPath")
            if program_files_path:
                for pf in (os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", "")):
                    if pf:
                        ff_exe = Path(pf) / program_files_path / "firefox.exe"
                        if ff_exe.exists():
                            exe_path = str(ff_exe)
                            break

            version = BrowserDetection._get_file_version(exe_path) if exe_path else "Unknown"

            browsers.append({
                "name": f"{alias} (Gecko)",
                "type": "Gecko",
                "engineFamily": browser_def.get("engineFamily", "Firefox"),
                "profile_path": profile_path,
                "exe_path": exe_path,
                "process_name": process_name,
                "version": version,
                "raw_name": alias,
                "icon": browser_def.get("icon", alias.lower()),
                "detectStrategy": detect_strategy
            })

        return browsers

    @staticmethod
    def get_installed_browsers():
        return BrowserDetection.get_chromium_browsers() + BrowserDetection.get_gecko_browsers()

    @staticmethod
    def is_browser_running(browser):
        """Check if browser process is currently running."""
        process_name = browser.get("process_name", "")
        if not process_name:
            return False
        try:
            result = subprocess.run(
                ["tasklist", "/FI", f"IMAGENAME eq {process_name}.exe"],
                capture_output=True, text=True, timeout=10
            )
            return process_name.lower() in result.stdout.lower()
        except Exception:
            return False

    @staticmethod
    def test_browser_running(browser):
        """Alias for is_browser_running — kept for GUI backward compatibility."""
        return BrowserDetection.is_browser_running(browser)

    @staticmethod
    def get_browser_profiles(browser):
        profiles = []
        btype = browser.get("type", "")
        detect_strategy = browser.get("detectStrategy", "")

        if btype == "Chromium" or detect_strategy == "localState":
            user_data_path = Path(browser["profile_path"])
            if user_data_path.exists():
                # Read profile metadata from Local State info_cache
                info_cache = {}
                local_state_path = user_data_path / "Local State"
                if local_state_path.exists():
                    try:
                        ls_data = json.loads(local_state_path.read_text(encoding="utf-8"))
                        info_cache = ls_data.get("profile", {}).get("info_cache", {})
                    except Exception:
                        pass

                if info_cache:
                    # TRUTH SOURCE: read profiles from info_cache keys.
                    # Pre-compute all profile sizes in parallel so the GUI
                    # doesn't pay a sequential O(N) disk walk per refresh.
                    candidates = {dn: user_data_path / dn for dn in info_cache or {}}
                    existing = {dn: p for dn, p in candidates.items() if p.is_dir()}
                    sizes = BrowserDetection._get_dir_sizes_parallel(list(existing.values())) if existing else {}
                    for dir_name, meta in info_cache.items():
                        item = existing.get(dir_name)
                        if item is None:
                            continue
                        size = sizes.get(str(item), 0)
                        profiles.append({
                            "name": dir_name,
                            "display_name": meta.get("name", ""),
                            "email": meta.get("gaia_name", "") or meta.get("user_name", "") or meta.get("gaia_email", "") or meta.get("signed_in_email", ""),
                            "full_path": str(item),
                            "size_mb": round(size / (1024 * 1024), 2),
                            "is_default": dir_name == "Default"
                        })
                else:
                    # Fallback: scan directories if info_cache unavailable
                    candidates = [
                        item for item in user_data_path.iterdir()
                        if item.is_dir() and (
                            item.name == "Default"
                            or re.match(r'^Profile \d+$', item.name)
                            or item.name.endswith("-release")
                            or item.name.endswith("-beta")
                        )
                    ]
                    sizes = BrowserDetection._get_dir_sizes_parallel(candidates) if candidates else {}
                    for item in candidates:
                        size = sizes.get(str(item), 0)
                        profiles.append({
                            "name": item.name,
                            "display_name": "",
                            "email": "",
                            "full_path": str(item),
                            "size_mb": round(size / (1024 * 1024), 2),
                            "is_default": item.name == "Default"
                        })

        elif btype == "Gecko" and detect_strategy == "localProfilesDir":
            # Zen-style: profiles in profile_path/Profiles/<hash>.<name>
            profiles_dir = Path(browser["profile_path"]) / "Profiles"
            if profiles_dir.exists():
                for item in profiles_dir.iterdir():
                    if item.is_dir():
                        size = _quick_size(str(item))
                        # Strip <hash>. prefix for display name (e.g. "9pr8v7oq.Default Profile" -> "Default Profile")
                        display_name = item.name
                        dot_idx = item.name.find(".")
                        if dot_idx > 0:
                            display_name = item.name[dot_idx + 1:]
                        profiles.append({
                            "name": item.name,
                            "display_name": display_name,
                            "email": "",
                            "full_path": str(item),
                            "size_mb": round(size / (1024 * 1024), 2),
                            "is_default": len(profiles) == 0
                        })

        elif btype == "Gecko" or detect_strategy == "profilesIni":
            firefox_root = Path(browser["profile_path"])
            profiles_ini = firefox_root / "profiles.ini"
            if profiles_ini.exists():
                try:
                    content = profiles_ini.read_text(encoding='utf-8', errors='ignore')
                    sections = re.split(r'\[Profile\d*\]', content)
                    for i, section in enumerate(sections[1:]):
                        name_match = re.search(r'^Name=(.+)$', section, re.MULTILINE)
                        path_match = re.search(r'^Path=(.+)$', section, re.MULTILINE)

                        if path_match:
                            p_path = firefox_root / path_match.group(1).strip()
                            if p_path.exists():
                                size = _quick_size(str(p_path))
                                profiles.append({
                                    "name": name_match.group(1).strip() if name_match else f"Profile{i}",
                                    "full_path": str(p_path),
                                    "size_mb": round(size / (1024 * 1024), 2),
                                    "is_default": i == 0
                                })
                except Exception as e:
                    log.error(f"Error parsing Firefox profiles: {e}")

        return profiles

    @staticmethod
    def get_profile_backup_summary(profile_path):
        """Get a quick summary of what will be backed up for a profile.

        Returns:
        {
            "critical_files": [{"name": "Login Data", "exists": True, "size_kb": 12.3}, ...],
            "critical_count": "8/8",
            "total_size_mb": 123.4,
            "estimated_size_mb": 45.6,  # after exclusions
            "file_count": 1567,
        }
        """
        from core.backup import BackupEngine
        profile = Path(profile_path)
        if not profile.exists():
            return {"critical_count": "0/8", "total_size_mb": 0, "estimated_size_mb": 0, "file_count": 0, "critical_files": []}

        critical = BackupEngine.get_critical_files_status(profile_path)
        backed_up = sum(1 for c in critical if c["exists"])
        total_critical = len(critical)

        # Get size estimate (with exclusions)
        estimate = BackupEngine.estimate_backup_size(profile_path)

        return {
            "critical_files": critical,
            "critical_count": f"{backed_up}/{total_critical}",
            "total_size_mb": estimate.get("total_size_mb", 0),
            "estimated_size_mb": estimate.get("total_size_mb", 0),
            "file_count": estimate.get("file_count", 0),
            "excluded_size_mb": estimate.get("excluded_size_mb", 0),
        }

    @staticmethod
    def _get_dir_size(path):
        """Get directory size in bytes.  Cached for 30 seconds.

        Uses _full_size so the reported byte count matches the backup
        engine's actual walk (so the GUI's "1.3 GB" matches what the
        backup will transfer).  Repeated calls within 30s return instantly
        via cache.
        """
        path_str = str(path)
        cached = _size_cache_get(path_str)
        if cached is not None:
            return cached
        size = _full_size(path_str)
        _size_cache_set(path_str, size)
        return size

    @staticmethod
    def _get_dir_sizes_parallel(paths):
        """Walk a list of directory paths in parallel and return their sizes.

        For 7 Chrome profiles this drops ~600 ms sequential scan to
        ~150 ms parallel wall-time.  Results are cached so subsequent
        refreshes are free.
        """
        from concurrent.futures import ThreadPoolExecutor

        unseen = [p for p in paths if _size_cache_get(str(p)) is None]
        if unseen:
            with ThreadPoolExecutor(max_workers=min(8, len(unseen) or 1)) as ex:
                for p, size in zip(unseen, ex.map(_full_size, unseen)):
                    _size_cache_set(str(p), size)
        return {str(p): (_size_cache_get(str(p)) or 0) for p in paths}

    @staticmethod
    def clear_size_cache():
        """Invalidate the size cache.  Called after a backup/restore completes."""
        _SIZE_CACHE.clear()

    @staticmethod
    def _get_file_version(path):
        if not path:
            return "Unknown"
        try:
            cmd = f'(Get-Item "{path}").VersionInfo.ProductVersion'
            result = subprocess.run(["powershell", "-NoProfile", "-Command", cmd],
                                    capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception:
            pass

        try:
            import win32api
            info = win32api.GetFileVersionInfo(path, "\\")
            ms = info.get('FileVersionMS', 0)
            ls = info.get('FileVersionLS', 0)
            return f"{ms >> 16}.{ms & 0xFFFF}.{ls >> 16}.{ls & 0xFFFF}"
        except Exception:
            pass

        return "Unknown"