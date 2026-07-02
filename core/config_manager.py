# core/config_manager.py
import json
import os
from pathlib import Path

class ConfigManager:
    def __init__(self, config_path=None):
        if config_path is None:
            config_path = self._find_config()
        self.config = self._load_config(config_path)

    def _find_config(self):
        # 1. Check AppData
        appdata = os.environ.get("APPDATA", "")
        if appdata:
            appdata_config = Path(appdata) / "UniversalBrowserBackup" / "browsers.json"
            if appdata_config.exists():
                return str(appdata_config)

        # 2. Check project Config folder (note: capital C "Config")
        project_config = Path(__file__).parent.parent / "Config" / "browsers.json"
        if project_config.exists():
            return str(project_config)

        return None

    def _load_config(self, path):
        if path and os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Error loading config: {e}")

        # Defaults matching Config/browsers.json schema
        return {
            "version": "2.1.0",
            "defaults": {
                "backupDestination": os.path.join(os.environ.get("USERPROFILE", ""), "Desktop"),
                "excludeFromBackup": [
                    "Cache", "Code Cache", "Service Worker", "cache2",
                    "startupCache", "GPUCache", "Thumbnails", "blob_storage",
                    "Network", "Session Storage", "File System", "Storage",
                    "ShaderCache", "GrShaderCache", "GraphiteDawnCache",
                    "DawnWebGPUCache", "Local Storage", "IndexedDB", "Visited Links"
                ],
                "robocopyRetries": 3,
                "robocopyWait": 2,
                "maxLogFiles": 30,
                "checksumCriticalFiles": [
                    "Bookmarks", "Bookmarks.bak", "History", "Login Data",
                    "Preferences", "Secure Preferences", "Cookies", "Web Data"
                ]
            },
            "chromiumPaths": {
                "local": [
                    "Google\\Chrome", "Microsoft\\Edge", "BraveSoftware\\Brave-Browser",
                    "Vivaldi", "Opera Software\\Opera Stable", "Opera Software\\Opera GX Stable",
                    "Arc\\User Data", "Floorp", "Zen Browser", "Thorium", "Ladybird",
                    "Iron", "SRWare Iron", "Epic Privacy Browser", "Comodo Dragon",
                    "Yandex\\YandexBrowser", "Samsung\\Internet", "Avast Browser",
                    "AVG Secure Browser", "CCleaner Browser", "UC Browser", "Chromium"
                ],
                "programFiles": [
                    "Google\\Chrome", "Microsoft\\Edge", "BraveSoftware\\Brave-Browser",
                    "Vivaldi", "Opera\\Opera stable", "Opera Software\\Opera GX Stable",
                    "Thorium", "Ladybird"
                ]
            },
            "geckoPaths": {
                "appData": "Mozilla\\Firefox",
                "localAppData": "Mozilla\\Firefox"
            },
            "processNames": {
                "Chrome": "chrome",
                "Edge": "msedge",
                "Brave-Browser": "brave",
                "Vivaldi": "vivaldi",
                "Opera Stable": "opera",
                "Opera GX Stable": "opera",
                "Opera stable": "opera",
                "Arc": "Arc",
                "Floorp": "floorp",
                "Zen Browser": "zen",
                "Thorium": "thorium",
                "Ladybird": "ladybird",
                "Iron": "iron",
                "SRWare Iron": "iron",
                "Epic Privacy Browser": "epic",
                "Comodo Dragon": "dragon",
                "YandexBrowser": "browser",
                "Internet": "browser",
                "Avast Browser": "avast",
                "AVG Secure Browser": "avg",
                "CCleaner Browser": "ccleaner",
                "UC Browser": "ucbrowser",
                "Chromium": "chromium"
            }
        }

    def get(self, key, default=None):
        return self.config.get(key, default)

    def get_default(self, key):
        return self.config.get("defaults", {}).get(key)

# Global config instance
config_manager = ConfigManager()
config = config_manager.config