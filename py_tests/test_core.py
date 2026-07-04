# py_tests/test_core.py
import unittest
import os
import sys
import json
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from core.config_manager import ConfigManager
from core.detection import BrowserDetection
from core.backup import BackupEngine, list_backups
from core.restore import RestoreEngine


class TestCoreLogic(unittest.TestCase):
    def setUp(self):
        self.cm = ConfigManager()
        self.tmp_dir = tempfile.mkdtemp(prefix="ubb_test_")

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_config_loading(self):
        dest = self.cm.get_default("backupDestination")
        self.assertIsNotNone(dest)
        self.assertTrue(len(dest) > 0)

    def test_browser_detection_structure(self):
        browsers = BrowserDetection.get_installed_browsers()
        self.assertIsInstance(browsers, list)

        for b in browsers:
            self.assertIn("name", b)
            self.assertIn("type", b)
            self.assertIn("profile_path", b)
            self.assertIn("process_name", b)

    def test_profile_discovery(self):
        browsers = BrowserDetection.get_installed_browsers()
        if browsers:
            browser = browsers[0]
            profiles = BrowserDetection.get_browser_profiles(browser)
            self.assertIsInstance(profiles, list)

    def test_config_has_checksum_critical_files(self):
        critical = self.cm.get_default("checksumCriticalFiles")
        self.assertIsInstance(critical, list)
        self.assertGreater(len(critical), 0)

    def test_config_has_process_names(self):
        process_names = self.cm.get("processNames")
        self.assertIsInstance(process_names, dict)
        self.assertGreater(len(process_names), 0)

    def test_browser_running_method(self):
        """Verify test_browser_running and is_browser_running exist and return booleans."""
        self.assertTrue(callable(getattr(BrowserDetection, 'test_browser_running', None)))
        self.assertTrue(callable(getattr(BrowserDetection, 'is_browser_running', None)))

        result = BrowserDetection.is_browser_running({
            "process_name": "definitelynotrealprocess12345"
        })
        self.assertIsInstance(result, bool)
        self.assertFalse(result)

    def test_list_backups_no_directory(self):
        """list_backups returns {} when destination is missing."""
        bogus = os.path.join(self.tmp_dir, "nonexistent")
        self.assertEqual(list_backups(bogus), {})

    def test_list_backups_with_samples(self):
        """list_backups returns manifest-bearing folders grouped by browser."""
        root = Path(self.tmp_dir)
        fake_backup = root / "Chrome_Default_20260101_120000"
        fake_backup.mkdir()
        (fake_backup / "manifest.json").write_text(json.dumps({
            "browser": {"name": "Chrome"},
            "profile": "Default",
            "timestamp": "2026-01-01T12:00:00",
            "stats": {"totalSizeMB": 123.45}
        }), encoding="utf-8")

        result = list_backups(root)
        self.assertIn("Chrome", result)
        self.assertEqual(len(result["Chrome"]), 1)
        self.assertEqual(result["Chrome"][0]["size_mb"], 123.45)

    def test_compare_backups(self):
        """compare_backups should report added/removed/modified files."""
        old = Path(self.tmp_dir) / "old"
        new = Path(self.tmp_dir) / "new"
        old.mkdir()
        new.mkdir()

        # Bookmarks is modified (different size)
        (old / "Bookmarks").write_text("aaa", encoding="utf-8")
        (old / "removed_only").write_text("a", encoding="utf-8")

        (new / "Bookmarks").write_text("bbbbbbbb", encoding="utf-8")
        (new / "added_only").write_text("c", encoding="utf-8")

        result = BackupEngine.compare_backups(str(old), str(new))
        self.assertIn("removed_only", result["files_only_in_old"])
        self.assertIn("added_only", result["files_only_in_new"])
        modified_paths = [f["path"] for f in result["files_modified"]]
        self.assertIn("Bookmarks", modified_paths)
        self.assertEqual(len(result["files_identical"]), 0)

    def test_verify_backup_no_manifest(self):
        """verify_backup should fail when manifest.json is missing."""
        result = BackupEngine.verify_backup(os.path.join(self.tmp_dir, "nope"))
        self.assertFalse(result["success"])

    def test_verify_backup_success(self):
        """verify_backup succeeds when manifest checksums match real files."""
        backup = Path(self.tmp_dir) / "good_backup"
        backup.mkdir()
        (backup / "Bookmarks").write_text("hello", encoding="utf-8")
        expected = BackupEngine.generate_checksum(str(backup / "Bookmarks"))
        manifest = {
            "version": "2.1.0",
            "checksums": {"Bookmarks": expected},
            "stats": {"fileCount": 1, "totalSizeMB": 0.0001}
        }
        (backup / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

        result = BackupEngine.verify_backup(str(backup))
        self.assertTrue(result["success"], msg=result.get("message"))

    def test_export_profile_zip(self):
        """export_profile_zip creates a valid .zip from a fake profile directory."""
        profile = Path(self.tmp_dir) / "Profile"
        profile.mkdir()
        (profile / "Bookmarks").write_text("{}", encoding="utf-8")
        (profile / "Cache").mkdir()
        (profile / "Cache" / "data").write_text("cache", encoding="utf-8")

        out_zip = Path(self.tmp_dir) / "out.zip"
        ok, msg = BackupEngine.export_profile_zip(
            {"name": "Test", "type": "Chromium"},
            {"name": "Default", "full_path": str(profile)},
            str(out_zip)
        )
        self.assertTrue(ok, msg=msg)
        self.assertTrue(out_zip.exists())
        self.assertGreater(out_zip.stat().st_size, 0)

    def test_restore_legacy_no_manifest_accepts_critical_files(self):
        """Restore should accept a backup that lacks manifest.json if it contains enough critical files."""
        backup = Path(self.tmp_dir) / "legacy_backup"
        backup.mkdir()

        # Mimic a Chromium User Data root with at least 3 critical files in nested profile
        profile = backup / "Default"
        profile.mkdir()
        (profile / "Bookmarks").write_text("{}", encoding="utf-8")
        (profile / "Login Data").write_text("x", encoding="utf-8")
        (profile / "Cookies").write_text("x", encoding="utf-8")
        (profile / "Preferences").write_text("x", encoding="utf-8")
        (backup / "Local State").write_text("{}", encoding="utf-8")

        # No manifest.json — verify should now accept
        v = RestoreEngine.verify_backup(str(backup), {"type": "Chromium", "name": "Chrome"})
        self.assertTrue(v["valid"], msg=v.get("message"))
        self.assertTrue(v["manifest"].get("_legacy_no_manifest"))

    def test_restore_legacy_no_manifest_rejects_too_few_files(self):
        """Restore should refuse a folder with < 3 critical files even without manifest."""
        backup = Path(self.tmp_dir) / "empty_backup"
        backup.mkdir()
        (backup / "Bookmarks").write_text("x", encoding="utf-8")

        v = RestoreEngine.verify_backup(str(backup), {"type": "Chromium", "name": "Chrome"})
        self.assertFalse(v["valid"])


if __name__ == "__main__":
    unittest.main()