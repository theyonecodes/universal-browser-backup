# core/logger.py
import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from datetime import datetime

class AppLogger:
    def __init__(self, app_name="UniversalBrowserBackup", log_dir=None, max_bytes=5*1024*1024, backup_count=30):
        if log_dir is None:
            log_dir = os.path.join(os.environ.get("APPDATA", ""), app_name, "logs")

        os.makedirs(log_dir, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.log_file = os.path.join(log_dir, f"backup_{timestamp}.log")

        self.logger = logging.getLogger(app_name)
        self.logger.setLevel(logging.DEBUG)
        self.logger.propagate = False  # Don't propagate to root

        # Clear existing handlers to avoid duplicates
        self.logger.handlers.clear()

        # File handler (Rotating)
        file_handler = RotatingFileHandler(
            self.log_file, maxBytes=max_bytes, backupCount=backup_count, encoding='utf-8'
        )
        file_formatter = logging.Formatter('[%(asctime)s] [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
        file_handler.setFormatter(file_formatter)

        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_formatter = logging.Formatter('[%(levelname)s] %(message)s')
        console_handler.setFormatter(console_formatter)

        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)

    def get_logger(self):
        return self.logger

    def get_log_path(self):
        return self.log_file

# Global logger instance - lazy initialization
_logger_instance = None

def _get_logger_instance():
    global _logger_instance
    if _logger_instance is None:
        _logger_instance = AppLogger()
    return _logger_instance

def get_logger():
    return _get_logger_instance().get_logger()

def get_log_path():
    return _get_logger_instance().get_log_path()

# Backwards compatible exports
log = get_logger()
log_path = get_log_path()