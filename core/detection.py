# core/detection.py
import os
import re
import subprocess
from pathlib import Path
from core.config_manager import config
from core.logger import log


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

            profile_path = None

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
                "profile_path": str(firefox_root),
                "exe_path": exe_path,
                "process_name": process_name,
                "version": version,
                "raw_name": alias,
                "icon": browser_def.get("icon", alias.lower()),
                "detectStrategy": browser_def.get("detectStrategy", "profilesIni")
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
                for item in user_data_path.iterdir():
                    if item.is_dir() and (item.name == "Default" or re.match(r'^Profile \d+$', item.name) or item.name.endswith("-release") or item.name.endswith("-beta")):
                        size = BrowserDetection._get_dir_size(item)
                        profiles.append({
                            "name": item.name,
                            "full_path": str(item),
                            "size_mb": round(size / (1024 * 1024), 2),
                            "is_default": item.name == "Default"
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
                                size = BrowserDetection._get_dir_size(p_path)
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
    def _get_dir_size(path):
        total = 0
        try:
            for entry in os.scandir(path):
                if entry.is_file(follow_symlinks=False):
                    total += entry.stat().st_size
                elif entry.is_dir(follow_symlinks=False):
                    total += BrowserDetection._get_dir_size(entry.path)
        except Exception:
            pass
        return total

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