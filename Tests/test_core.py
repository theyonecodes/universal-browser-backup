import pytest
import tempfile
import os
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import the modules to test
from core.backup import BackupEngine
from core.restore import RestoreEngine
from core.encryption import encrypt_file, decrypt_file, derive_key
from core.detection import BrowserDetection
from core.config_manager import config_manager, config


class TestBackupEngine:
    """Tests for BackupEngine"""
    
    def test_generate_checksum(self):
        """Test SHA-256 checksum generation"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write("test content")
            temp_path = f.name
        
        try:
            checksum = BackupEngine.generate_checksum(temp_path)
            assert len(checksum) == 64  # SHA-256 hex length
            assert all(c in '0123456789abcdef' for c in checksum)
        finally:
            os.unlink(temp_path)
    
    def test_get_critical_files_status(self):
        """Test critical files status detection"""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create some critical files
            critical_files = ["Login Data", "Cookies", "Preferences"]
            for fname in critical_files:
                with open(os.path.join(temp_dir, fname), 'w') as f:
                    f.write("test")
            
            status = BackupEngine.get_critical_files_status(temp_dir)
            assert len(status) == 3
            for item in status:
                assert item["exists"] is True
                assert item["size_kb"] >= 0
    
    def test_estimate_backup_size(self):
        """Test backup size estimation"""
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create some test files
            with open(os.path.join(temp_dir, "test.txt"), 'w') as f:
                f.write("x" * 1000)
            
            result = BackupEngine.estimate_backup_size(temp_dir)
            assert "total_size_mb" in result
            assert "file_count" in result
            assert result["file_count"] >= 1


class TestEncryption:
    """Tests for encryption module"""
    
    def test_derive_key(self):
        """Test key derivation"""
        salt = os.urandom(16)
        key1 = derive_key("test_password", salt)
        key2 = derive_key("test_password", salt)
        assert key1 == key2
        assert len(key1) == 32  # 256-bit key
    
    def test_encrypt_decrypt_file(self):
        """Test file encryption and decryption"""
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write("test content for encryption")
            input_path = f.name
        
        output_path = input_path + ".enc"
        decrypted_path = input_path + ".dec"
        
        try:
            # Encrypt
            meta = encrypt_file(input_path, output_path, "test_password")
            assert meta["encrypted"] is True
            assert meta["algorithm"] == "AES-256-GCM"
            
            # Decrypt
            success = decrypt_file(output_path, decrypted_path, "test_password", meta)
            assert success is True
            
            # Verify content
            with open(decrypted_path, 'r') as f:
                content = f.read()
            assert content == "test content for encryption"
        finally:
            for p in [input_path, output_path, decrypted_path]:
                if os.path.exists(p):
                    os.unlink(p)
    
    def test_encrypt_decrypt_bytes(self):
        """Test in-memory encryption/decryption"""
        data = b"test binary data"
        password = "test_password"
        
        encrypted, meta = encrypt_bytes(data, password)
        decrypted = decrypt_bytes(encrypted, password, meta)
        
        assert decrypted == data


class TestBrowserDetection:
    """Tests for BrowserDetection"""
    
    def test_get_installed_browsers(self):
        """Test browser detection returns list"""
        browsers = BrowserDetection.get_installed_browsers()
        assert isinstance(browsers, list)
        for browser in browsers:
            assert "name" in browser
            assert "version" in browser
            assert "type" in browser
    
    def test_get_browser_profiles(self):
        """Test profile detection for known browsers"""
        # This will return empty list on systems without browsers
        profiles = BrowserDetection.get_browser_profiles({"name": "Chrome", "type": "Chromium"})
        assert isinstance(profiles, list)


class TestConfigManager:
    """Tests for config manager"""
    
    def test_get_default(self):
        """Test default config retrieval"""
        dest = config_manager.get_default("backupDestination")
        assert isinstance(dest, str)
        assert len(dest) > 0
    
    def test_exclude_from_backup(self):
        """Test exclude dirs config"""
        excl = config.get_default("excludeFromBackup")
        assert isinstance(excl, list)
        assert "Cache" in excl


if __name__ == "__main__":
    pytest.main([__file__, "-v"])