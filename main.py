import sys
import os
import json
import argparse
import platform
from datetime import datetime
from pathlib import Path

try:
    from PySide6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QTabWidget, QComboBox, QPushButton, QLabel, QFileDialog,
        QLineEdit, QTextEdit, QMessageBox, QProgressBar, QCheckBox,
        QListWidget, QListWidgetItem, QGroupBox, QGridLayout, QScrollArea,
        QSpinBox, QSplitter, QFrame, QStatusBar, QFormLayout,
        QTableWidget, QTableWidgetItem, QHeaderView
    )
    from PySide6.QtCore import Qt, QThread, Signal, Slot, QTimer
    from PySide6.QtGui import QFont, QIcon
except ImportError:
    import sys
    print("ERROR: Required dependencies (PySide6) are missing.")
    print("Please run 'setup.bat' to install all necessary packages.")
    if sys.platform == "win32":
        input("\nPress Enter to exit...")
    sys.exit(1)

from core.detection import BrowserDetection
from core.config_manager import config_manager, config
from core.backup import BackupEngine, list_backups
from core.restore import RestoreEngine
from core.logger import get_logger, get_log_path

log = get_logger()
log_path = get_log_path()

# Ensure we run from the script's directory (critical for double-click execution)
script_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(script_dir)

_QT_NAMES = "QApplication QMainWindow QWidget QVBoxLayout QHBoxLayout QTabWidget QComboBox QPushButton QLabel QFileDialog QLineEdit QTextEdit QMessageBox QProgressBar QCheckBox QListWidget QListWidgetItem QGroupBox QGridLayout QScrollArea QSpinBox QSplitter QFrame QStatusBar QFormLayout QTableWidget QTableWidgetItem QHeaderView Qt QThread Signal Slot QTimer QFont QIcon".split()


def _import_qt():
    """Lazy import of PySide6 QtWidgets + QtCore + QtGui.

    Returning a namespace object keeps call sites unchanged (QApplication,
    QMainWindow, ...).  Imported only when the GUI is actually about to
    run, which keeps CLI mode ~250 ms faster.
    """
    import types
    import importlib
    from PySide6.QtWidgets import (  # noqa: F401
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QTabWidget, QComboBox, QPushButton, QLabel, QFileDialog,
        QLineEdit, QTextEdit, QMessageBox, QProgressBar, QCheckBox,
        QListWidget, QListWidgetItem, QGroupBox, QGridLayout, QScrollArea,
        QSpinBox, QSplitter, QFrame, QStatusBar, QFormLayout,
        QTableWidget, QTableWidgetItem, QHeaderView,
    )
    from PySide6.QtCore import Qt, QThread, Signal, Slot, QTimer  # noqa: F401
    from PySide6.QtGui import QFont, QIcon  # noqa: F401
    ns = types.SimpleNamespace()
    for name in _QT_NAMES:
        ns.__dict__[name] = locals()[name]
    return ns

class BrowserListItem(QWidget):
    """Custom widget for browser list with checkbox and info."""
    def __init__(self, browser_data, on_changed=None, parent=None):
        super().__init__(parent)
        self.browser_data = browser_data
        self.on_changed = on_changed
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(8)

        self.checkbox = QCheckBox()
        self.checkbox.setChecked(True)
        self.checkbox.toggled.connect(self._on_toggled)
        layout.addWidget(self.checkbox)

        name_label = QLabel(f"<b>{browser_data['name']}</b>")
        name_label.setMinimumWidth(180)
        layout.addWidget(name_label)

        version = browser_data.get('version', 'Unknown')
        type_label = QLabel(f"v{version} - {browser_data.get('type', 'Unknown')}")
        type_label.setStyleSheet("color: #666; font-size: 11px;")
        layout.addWidget(type_label)

        layout.addStretch()
        self.running_label = QLabel()
        self.update_running_label(False)
        layout.addWidget(self.running_label)

    def update_running_label(self, is_running):
        if is_running:
            self.running_label.setText("[RUNNING]")
            self.running_label.setStyleSheet("color: #f39c12; font-weight: bold; font-size: 11px;")
        else:
            self.running_label.setText("[stopped]")
            self.running_label.setStyleSheet("color: #95a5a6; font-size: 10px;")

    def is_checked(self):
        return self.checkbox.isChecked()

    def set_checked(self, checked):
        self.checkbox.setChecked(checked)

    def _on_toggled(self, checked):
        if self.on_changed:
            self.on_changed()


class ProfileListItem(QWidget):
    """Custom widget for profile list with checkbox and info."""
    def __init__(self, profile_data, parent=None):
        super().__init__(parent)
        self.profile_data = profile_data
        layout = QHBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(8)

        self.checkbox = QCheckBox()
        self.checkbox.setChecked(True)
        layout.addWidget(self.checkbox)

        name = profile_data["name"]
        display_name = profile_data.get("display_name", "")
        email = profile_data.get("email", "")
        size = profile_data["size_mb"]
        is_default = profile_data.get("is_default", False)

        # Build label: "Default — Your Chrome (theyonecodes@gmail.com) (Default) (123.4 MB)"
        label_text = f"<b>{name}</b>"
        if display_name and display_name != name:
            label_text += f" — {display_name}"
        if email:
            label_text += f" <span style='color:#888;'>({email})</span>"
        if is_default:
            label_text += " <i>(Default)</i>"
        size_text = f" <span style='color:#666;'>({size:.1f} MB)</span>"
        self.label = QLabel(label_text + size_text)
        self.label.setMinimumWidth(400)
        layout.addWidget(self.label)
        layout.addStretch()

        # Critical files summary — shows what preserves logins
        self.detail_label = QLabel()
        self.detail_label.setStyleSheet("color: #7f8c8d; font-size: 10px;")
        self.detail_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.detail_label)

        # Load critical files status in background to avoid UI freeze
        self._load_detail(profile_data.get("full_path", ""))

    def _load_detail(self, profile_path):
        """Populate the detail label with critical files + estimated size."""
        if not profile_path:
            self.detail_label.setText("")
            return
        try:
            from core.detection import BrowserDetection
            summary = BrowserDetection.get_profile_backup_summary(profile_path)
            critical = summary.get("critical_files", [])
            backed_up = sum(1 for c in critical if c["exists"])
            total = len(critical)
            est = summary.get("estimated_size_mb", 0)
            excluded = summary.get("excluded_size_mb", 0)
            file_count = summary.get("file_count", 0)

            # Build compact line: "8/8 critical ✓ | 234 files | 45.6 MB (excl 12.3 MB cache)"
            parts = []
            parts.append(f"<span style='color:{'#2ecc71' if backed_up == total else '#e67e22'};'>{backed_up}/{total} critical ✓</span>")
            parts.append(f"{file_count} files")
            if excluded > 0:
                parts.append(f"{est:.1f} MB (excl {excluded:.1f} MB cache)")
            else:
                parts.append(f"{est:.1f} MB")
            self.detail_label.setText(" | ".join(parts))
        except Exception:
            self.detail_label.setText("")

    def is_checked(self):
        return self.checkbox.isChecked()

    def set_checked(self, checked):
        self.checkbox.setChecked(checked)


class _WorkerDetect(QThread):
    """Background detection worker.

    The GUI calls refresh_browsers() which calls BrowserDetection, but the
    BrowserDetection scan walks every profile directory on disk.  For a
    Chrome install with 7 profiles that takes ~1 second; running it on the
    GUI thread froze the window before any pixels rendered.

    _WorkerDetect performs the disk+registry scan off-thread.  When done
    it emits a Signal carrying the list of browser dicts; MainWindow pops
    that into the UI list.
    """

    detected = Signal(list)

    def __init__(self, parent=None):
        super().__init__(parent)

    def run(self):
        try:
            browsers = BrowserDetection.get_installed_browsers()
            for b in browsers:
                try:
                    b["_profiles"] = BrowserDetection.get_browser_profiles(b)
                except Exception:
                    b["_profiles"] = []
            self.detected.emit(browsers)
        except Exception as e:
            log.error(f"Detection worker failed: {e}")
            self.detected.emit([])


class Worker(QThread):
    finished = Signal(dict)
    progress = Signal(str)
    progress_value = Signal(int, int)
    log_message = Signal(str)

    def __init__(self, task_type, params_list):
        super().__init__()
        self.task_type = task_type
        self.params_list = params_list
        self._cancelled = False

    def cancel(self):
        self._cancelled = True

    def run(self):
        try:
            total = len(self.params_list)
            for i, params in enumerate(self.params_list):
                if self._cancelled:
                    self.finished.emit({"success": False, "cancelled": True, "message": "Operation cancelled"})
                    return

                item_name = params.get('profile_name') or params.get('backup_path') or params.get('item_label', 'item')
                self.progress.emit(f"Processing {item_name} ({i+1}/{total})...")
                self.progress_value.emit(i + 1, total)

                if self.task_type == "backup":
                    result = BackupEngine.run_backup(**params)
                elif self.task_type == "restore":
                    result = RestoreEngine.run_restore(**params)
                elif self.task_type == "verify":
                    result = BackupEngine.verify_backup(**params)
                else:
                    result = {"success": False, "message": f"Unknown task: {self.task_type}"}

                if not result.get("success", False):
                    self.finished.emit({"success": False, "message": f"{item_name}: {result.get('message', 'Unknown error')}"})
                    return

            self.finished.emit({"success": True, "message": f"All {total} item(s) completed successfully"})
        except Exception as e:
            self.log_message.emit(f"Worker exception: {e}")
            self.finished.emit({"success": False, "message": str(e)})


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Universal Browser Backup v2.1.1")
        self.setMinimumSize(950, 700)
        self.resize(1050, 750)

        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.layout = QVBoxLayout(self.central_widget)

        self.tabs = QTabWidget()
        self.layout.addWidget(self.tabs)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("Ready")

        self.browsers = []
        self.worker = None
        self.backup_schedule_timer = None

        self.init_backup_tab()
        self.init_restore_tab()
        self.init_verify_tab()
        self.init_saved_backups_tab()
        self.init_schedule_tab()
        self.init_export_import_tab()
        self.init_logs_tab()

        # Initialise empty UI lists so the window renders immediately.  The
        # actual browser/profile data is populated asynchronously by
        # _WorkerDetect (a QThread) so the GUI doesn't freeze for ~1s
        # while we walk 7 Chrome profiles' directories.
        self.browsers = []
        self._detect_worker = None

        # Kick off the disk scan on a worker thread.  The window renders
        # immediately; browsers/profile lists populate when the worker emits
        # its Signal.  Without this the GUI froze for ~1s on profile-dir scans.
        self._kick_async_detection()

    def _kick_async_detection(self):
        """Start detection on a worker thread; populate UI when done."""
        # Worker still has to be referenced somewhere so GC doesn't kill it
        self._detect_worker = _WorkerDetect(self)
        self._detect_worker.detected.connect(self._on_detection_done)
        self._detect_worker.start()

    def init_backup_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(12)

        # --- Browser Selection (MULTI-SELECT now) ---
        browser_group = QGroupBox("1. Select Browsers (multi-select)")
        browser_layout = QVBoxLayout(browser_group)

        browser_toolbar = QHBoxLayout()
        browser_toolbar.addWidget(QLabel("Browsers:"))
        browser_toolbar.addStretch()
        self.btn_select_all_browsers = QPushButton("Select All")
        self.btn_select_all_browsers.clicked.connect(lambda: self.set_all_browsers(True))
        browser_toolbar.addWidget(self.btn_select_all_browsers)
        self.btn_deselect_all_browsers = QPushButton("Deselect All")
        self.btn_deselect_all_browsers.clicked.connect(lambda: self.set_all_browsers(False))
        browser_toolbar.addWidget(self.btn_deselect_all_browsers)
        self.btn_refresh = QPushButton("Refresh")
        self.btn_refresh.clicked.connect(self.refresh_browsers)
        browser_toolbar.addWidget(self.btn_refresh)
        browser_layout.addLayout(browser_toolbar)

        self.browser_list = QListWidget()
        self.browser_list.setAlternatingRowColors(True)
        self.browser_list.setMinimumHeight(110)
        browser_layout.addWidget(self.browser_list)

        layout.addWidget(browser_group)

        # --- Profile Selection ---
        profile_group = QGroupBox("2. Select Profiles")
        profile_layout = QVBoxLayout(profile_group)

        toolbar = QHBoxLayout()
        self.chk_all_profiles = QCheckBox("All Profiles for selected browsers")
        self.chk_all_profiles.setChecked(True)
        self.chk_all_profiles.toggled.connect(self.toggle_all_profiles)
        toolbar.addWidget(self.chk_all_profiles)

        self.btn_select_all = QPushButton("Select All")
        self.btn_select_all.clicked.connect(lambda: self.set_all_profiles(True))
        toolbar.addWidget(self.btn_select_all)

        self.btn_deselect_all = QPushButton("Deselect All")
        self.btn_deselect_all.clicked.connect(lambda: self.set_all_profiles(False))
        toolbar.addWidget(self.btn_deselect_all)

        toolbar.addStretch()
        self.profile_count_label = QLabel("0 profiles")
        toolbar.addWidget(self.profile_count_label)
        profile_layout.addLayout(toolbar)

        # Profile Table
        self.profile_table = QTableWidget()
        self.profile_table.setAlternatingRowColors(True)
        self.profile_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.profile_table.setSelectionMode(QTableWidget.ExtendedSelection)
        self.profile_table.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.profile_table.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.profile_table.setColumnCount(8)
        self.profile_table.setHorizontalHeaderLabels([
            "✓", "Browser", "Profile", "Display Name", "Email", "Critical Files", "Est. Size", "Default"
        ])
        header = self.profile_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.Fixed)
        header.setSectionResizeMode(1, QHeaderView.Interactive)
        header.setSectionResizeMode(2, QHeaderView.Interactive)
        header.setSectionResizeMode(3, QHeaderView.Stretch)
        header.setSectionResizeMode(4, QHeaderView.Stretch)
        header.setSectionResizeMode(5, QHeaderView.Interactive)
        header.setSectionResizeMode(6, QHeaderView.Interactive)
        header.setSectionResizeMode(7, QHeaderView.Fixed)
        self.profile_table.setColumnWidth(0, 40)
        self.profile_table.setColumnWidth(7, 60)
        profile_layout.addWidget(self.profile_table)

        layout.addWidget(profile_group)

        # --- Destination ---
        dest_group = QGroupBox("3. Backup Destination")
        dest_layout = QHBoxLayout(dest_group)
        dest_layout.addWidget(QLabel("Folder:"))
        self.dest_edit = QLineEdit(os.path.expandvars(config_manager.get_default("backupDestination")))
        self.dest_edit.setPlaceholderText("Click Browse or type path...")
        dest_layout.addWidget(self.dest_edit)
        self.btn_browse_dest = QPushButton("Browse...")
        self.btn_browse_dest.clicked.connect(self.browse_destination)
        dest_layout.addWidget(self.btn_browse_dest)
        layout.addWidget(dest_group)

        # --- Options ---
        opt_group = QGroupBox("Options")
        opt_layout = QHBoxLayout(opt_group)
        self.chk_force = QCheckBox("Force Close Browser")
        self.chk_force.setToolTip("Kill browser process if running (may lose unsaved data)")
        opt_layout.addWidget(self.chk_force)
        self.chk_exclude_cache = QCheckBox("Exclude Cache")
        self.chk_exclude_cache.setChecked(True)
        self.chk_exclude_cache.setToolTip("Skip cache, thumbnails, service workers, shader caches, etc.")
        opt_layout.addWidget(self.chk_exclude_cache)
        self.chk_verify_after = QCheckBox("Verify after backup")
        self.chk_verify_after.setChecked(True)
        self.chk_verify_after.setToolTip("Run integrity check on the backup after creation")
        opt_layout.addWidget(self.chk_verify_after)
        opt_layout.addStretch()
        layout.addWidget(opt_group)

        # --- Action Buttons ---
        action_layout = QHBoxLayout()
        self.btn_backup = QPushButton("Start Backup")
        self.btn_backup.setMinimumHeight(44)
        backup_style = (
            "QPushButton { background-color: #27ae60; color: white; font-weight: bold; font-size: 14px; border-radius: 6px; padding: 6px 18px; }"
            "QPushButton:hover { background-color: #2ecc71; }"
            "QPushButton:pressed { background-color: #219a52; }"
            "QPushButton:disabled { background-color: #7f8c8d; }"
        )
        self.btn_backup.setStyleSheet(backup_style)
        self.btn_backup.clicked.connect(self.start_backup)
        action_layout.addWidget(self.btn_backup)

        self.btn_cancel = QPushButton("Cancel")
        self.btn_cancel.setMinimumHeight(44)
        cancel_style = (
            "QPushButton { background-color: #e67e22; color: white; font-weight: bold; font-size: 13px; border-radius: 6px; padding: 6px 18px; }"
            "QPushButton:hover { background-color: #f39c12; }"
            "QPushButton:disabled { background-color: #7f8c8d; }"
        )
        self.btn_cancel.setStyleSheet(cancel_style)
        self.btn_cancel.clicked.connect(self.cancel_task)
        self.btn_cancel.setEnabled(False)
        action_layout.addWidget(self.btn_cancel)
        layout.addLayout(action_layout)

        # --- Progress ---
        self.backup_progress = QProgressBar()
        self.backup_progress.setTextVisible(True)
        self.backup_progress.setFormat("%p% - %v/%m profiles")
        layout.addWidget(self.backup_progress)

        self.status_label = QLabel("Ready")
        self.status_label.setStyleSheet("color: #7f8c8d; font-size: 12px;")
        layout.addWidget(self.status_label)

        self.tabs.addTab(tab, "Backup")

    def init_restore_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(12)

        browser_group = QGroupBox("Target Browser")
        br_layout = QHBoxLayout(browser_group)
        br_layout.addWidget(QLabel("Restore to:"))
        self.res_browser_combo = QComboBox()
        self.res_browser_combo.setMinimumWidth(360)
        br_layout.addWidget(self.res_browser_combo)
        br_layout.addStretch()
        layout.addWidget(browser_group)

        profile_group = QGroupBox("Target Profile")
        pl_layout = QVBoxLayout(profile_group)
        self.res_profile_table = QTableWidget()
        self.res_profile_table.setAlternatingRowColors(True)
        self.res_profile_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.res_profile_table.setSelectionMode(QTableWidget.SingleSelection)
        self.res_profile_table.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.res_profile_table.setColumnCount(7)
        self.res_profile_table.setHorizontalHeaderLabels([
            "Browser", "Profile", "Display Name", "Email", "Critical Files", "Est. Size", "Default"
        ])
        r_header = self.res_profile_table.horizontalHeader()
        r_header.setSectionResizeMode(0, QHeaderView.Interactive)
        r_header.setSectionResizeMode(1, QHeaderView.Interactive)
        r_header.setSectionResizeMode(2, QHeaderView.Stretch)
        r_header.setSectionResizeMode(3, QHeaderView.Stretch)
        r_header.setSectionResizeMode(4, QHeaderView.Interactive)
        r_header.setSectionResizeMode(5, QHeaderView.Interactive)
        r_header.setSectionResizeMode(6, QHeaderView.Fixed)
        self.res_profile_table.setColumnWidth(6, 60)
        pl_layout.addWidget(self.res_profile_table)
        layout.addWidget(profile_group)

        src_group = QGroupBox("Backup Source")
        src_layout = QHBoxLayout(src_group)
        src_layout.addWidget(QLabel("Folder:"))
        self.src_edit = QLineEdit()
        self.src_edit.setPlaceholderText("Select backup folder (containing manifest.json)...")
        src_layout.addWidget(self.src_edit)
        self.btn_browse_src = QPushButton("Browse...")
        self.btn_browse_src.clicked.connect(self.browse_source)
        src_layout.addWidget(self.btn_browse_src)
        layout.addWidget(src_group)

        opt_group = QGroupBox("Options")
        opt_layout = QHBoxLayout(opt_group)
        self.res_chk_force = QCheckBox("Force Close Browser")
        self.res_chk_force.setToolTip("Kill browser process if running")
        opt_layout.addWidget(self.res_chk_force)
        self.res_chk_rollback = QCheckBox("Rollback on failure")
        self.res_chk_rollback.setChecked(True)
        self.res_chk_rollback.setToolTip("Create safety snapshot before restore")
        opt_layout.addWidget(self.res_chk_rollback)
        opt_layout.addStretch()
        layout.addWidget(opt_group)

        self.btn_restore = QPushButton("Start Restore")
        self.btn_restore.setMinimumHeight(44)
        restore_style = (
            "QPushButton { background-color: #e74c3c; color: white; font-weight: bold; font-size: 14px; border-radius: 6px; padding: 6px 18px; }"
            "QPushButton:hover { background-color: #ec7063; }"
            "QPushButton:pressed { background-color: #c0392b; }"
            "QPushButton:disabled { background-color: #7f8c8d; }"
        )
        self.btn_restore.setStyleSheet(restore_style)
        self.btn_restore.clicked.connect(self.start_restore)
        layout.addWidget(self.btn_restore)

        self.tabs.addTab(tab, "Restore")

        self.res_browser_combo.currentIndexChanged.connect(self.on_res_browser_changed)

    def init_verify_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(12)

        instr = QLabel("<i>Verify backup integrity by recomputing SHA-256 checksums and comparing against manifest.json</i>")
        instr.setStyleSheet("color:#555; padding:6px;")
        instr.setWordWrap(True)
        layout.addWidget(instr)

        list_group = QGroupBox("Existing Backups")
        gl_layout = QVBoxLayout(list_group)
        gl_layout.addLayout(self._make_helpers("verify_list"))
        self.verify_list = QListWidget()
        self.verify_list.setAlternatingRowColors(True)
        gl_layout.addWidget(self.verify_list)
        layout.addWidget(list_group)

        self.btn_verify = QPushButton("Verify Selected")
        self.btn_verify.setMinimumHeight(40)
        self.btn_verify.setStyleSheet(
            "QPushButton { background-color: #3498db; color:white; font-weight:bold; font-size:13px; border-radius:6px; padding:6px 16px; }"
            "QPushButton:hover { background-color:#5dade2; }"
            "QPushButton:disabled { background-color:#7f8c8d; }"
        )
        self.btn_verify.clicked.connect(self.verify_selected)
        layout.addWidget(self.btn_verify)

        self.verify_results = QTextEdit()
        self.verify_results.setReadOnly(True)
        self.verify_results.setFontFamily("Consolas, Courier New, monospace")
        self.verify_results.setFontPointSize(10)
        layout.addWidget(self.verify_results, stretch=1)

        self.tabs.addTab(tab, "Verify")

    def init_saved_backups_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(10)

        instr = QLabel("<i>List, inspect, delete and compare all backups produced by this tool</i>")
        instr.setStyleSheet("color:#555; padding:6px;")
        layout.addWidget(instr)

        toolbar = QHBoxLayout()
        self.btn_refresh_backups = QPushButton("Refresh")
        self.btn_refresh_backups.clicked.connect(self.refresh_saved_backups)
        toolbar.addWidget(self.btn_refresh_backups)
        self.btn_delete_backup = QPushButton("Delete")
        self.btn_delete_backup.clicked.connect(self.delete_selected_backup)
        toolbar.addWidget(self.btn_delete_backup)
        self.btn_compare_backups = QPushButton("Compare Two")
        self.btn_compare_backups.clicked.connect(self.compare_two_backups)
        toolbar.addWidget(self.btn_compare_backups)
        toolbar.addStretch()
        layout.addLayout(toolbar)

        splitter = QSplitter(Qt.Horizontal)
        self.backup_list_a = QListWidget()
        self.backup_list_a.setAlternatingRowColors(True)
        self.backup_list_b = QListWidget()
        self.backup_list_b.setAlternatingRowColors(True)
        splitter.addWidget(self.backup_list_a)
        splitter.addWidget(self.backup_list_b)
        splitter.setSizes([500, 500])
        layout.addWidget(splitter, stretch=2)

        self.compare_output = QTextEdit()
        self.compare_output.setReadOnly(True)
        self.compare_output.setFontFamily("Consolas, Courier New, monospace")
        layout.addWidget(self.compare_output, stretch=1)

        self.tabs.addTab(tab, "Backups")

    def init_schedule_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(12)

        instr = QLabel("<i>Schedule automatic backups at fixed intervals. Useful for nightly/hourly snapshots.</i>")
        instr.setStyleSheet("color:#555; padding:6px;")
        instr.setWordWrap(True)
        layout.addWidget(instr)

        cfg = QGroupBox("Schedule Configuration")
        cfg_layout = QFormLayout(cfg)

        self.schedule_enabled = QCheckBox("Enable scheduled backups")
        cfg_layout.addRow("Enable:", self.schedule_enabled)

        self.schedule_interval = QSpinBox()
        self.schedule_interval.setRange(1, 1440)
        self.schedule_interval.setSuffix(" minutes")
        self.schedule_interval.setValue(60)
        cfg_layout.addRow("Interval:", self.schedule_interval)

        self.schedule_dest_edit = QLineEdit(os.path.expandvars(config_manager.get_default("backupDestination")))
        dest_h = QHBoxLayout()
        dest_h.addWidget(self.schedule_dest_edit)
        btn_b = QPushButton("Browse...")
        btn_b.clicked.connect(lambda: self.browse_into(self.schedule_dest_edit))
        dest_h.addWidget(btn_b)
        self.schedule_dest_widget = QWidget()
        self.schedule_dest_widget.setLayout(dest_h)
        cfg_layout.addRow("Destination:", self.schedule_dest_widget)

        layout.addWidget(cfg)

        btn_layout = QHBoxLayout()
        btn_apply = QPushButton("Apply Schedule")
        btn_apply.clicked.connect(self.apply_schedule)
        btn_apply.setMinimumHeight(40)
        btn_apply.setStyleSheet(
            "QPushButton { background-color:#16a085; color:white; font-weight:bold; font-size:13px; border-radius:6px; padding:6px 16px; }"
            "QPushButton:hover { background-color:#1abc9c; }"
        )
        btn_layout.addWidget(btn_apply)
        btn_stop = QPushButton("Stop Schedule")
        btn_stop.clicked.connect(self.stop_schedule)
        btn_stop.setMinimumHeight(40)
        btn_stop.setStyleSheet(
            "QPushButton { background-color:#7f8c8d; color:white; font-weight:bold; font-size:13px; border-radius:6px; padding:6px 16px; }"
        )
        btn_layout.addWidget(btn_stop)
        layout.addLayout(btn_layout)

        self.schedule_status = QLabel("No schedule is currently active.")
        self.schedule_status.setStyleSheet("color:#555; font-style:italic; padding:8px;")
        layout.addWidget(self.schedule_status)

        layout.addStretch()
        self.tabs.addTab(tab, "Schedule")

    def init_export_import_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(12)

        instr = QLabel("<i>Export a profile (zip) and import one from another machine / earlier archive.</i>")
        instr.setStyleSheet("color:#555; padding:6px;")
        layout.addWidget(instr)

        # Export group
        ex_g = QGroupBox("Export Profile to Archive")
        ex_l = QVBoxLayout(ex_g)
        ex_browser = QHBoxLayout()
        ex_browser.addWidget(QLabel("Browser:"))
        self.export_browser_combo = QComboBox()
        ex_browser.addWidget(self.export_browser_combo)
        ex_browser.addStretch()
        ex_l.addLayout(ex_browser)

        self.export_profile_table = QTableWidget()
        self.export_profile_table.setAlternatingRowColors(True)
        self.export_profile_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.export_profile_table.setSelectionMode(QTableWidget.ExtendedSelection)
        self.export_profile_table.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.export_profile_table.setColumnCount(7)
        self.export_profile_table.setHorizontalHeaderLabels([
            "Browser", "Profile", "Display Name", "Email", "Critical Files", "Est. Size", "Default"
        ])
        ex_header = self.export_profile_table.horizontalHeader()
        ex_header.setSectionResizeMode(0, QHeaderView.Interactive)
        ex_header.setSectionResizeMode(1, QHeaderView.Interactive)
        ex_header.setSectionResizeMode(2, QHeaderView.Stretch)
        ex_header.setSectionResizeMode(3, QHeaderView.Stretch)
        ex_header.setSectionResizeMode(4, QHeaderView.Interactive)
        ex_header.setSectionResizeMode(5, QHeaderView.Interactive)
        ex_header.setSectionResizeMode(6, QHeaderView.Fixed)
        self.export_profile_table.setColumnWidth(6, 60)
        ex_l.addWidget(self.export_profile_table)

        ex_dest = QHBoxLayout()
        ex_dest.addWidget(QLabel("Output .zip:"))
        self.export_dest_edit = QLineEdit()
        ex_dest.addWidget(self.export_dest_edit)
        self.btn_browse_export = QPushButton("Save as...")
        self.btn_browse_export.clicked.connect(self.browse_export_path)
        ex_dest.addWidget(self.btn_browse_export)
        ex_l.addLayout(ex_dest)

        btn_export = QPushButton("Export Now")
        btn_export.clicked.connect(self.export_profile)
        btn_export.setMinimumHeight(40)
        btn_export.setStyleSheet(
            "QPushButton { background-color:#2980b9; color:white; font-weight:bold; font-size:13px; border-radius:6px; padding:6px 16px; }"
            "QPushButton:hover { background-color:#3498db; }"
        )
        ex_l.addWidget(btn_export)
        layout.addWidget(ex_g)

        # Import group
        im_g = QGroupBox("Import Archived Profile")
        im_l = QVBoxLayout(im_g)
        im_src = QHBoxLayout()
        im_src.addWidget(QLabel("Archive .zip:"))
        self.import_src_edit = QLineEdit()
        im_src.addWidget(self.import_src_edit)
        self.btn_browse_import = QPushButton("Select...")
        self.btn_browse_import.clicked.connect(self.browse_import_path)
        im_src.addWidget(self.btn_browse_import)
        im_l.addLayout(im_src)

        btn_import = QPushButton("Import Now")
        btn_import.clicked.connect(self.import_profile)
        btn_import.setMinimumHeight(40)
        btn_import.setStyleSheet(
            "QPushButton { background-color:#8e44ad; color:white; font-weight:bold; font-size:13px; border-radius:6px; padding:6px 16px; }"
            "QPushButton:hover { background-color:#9b59b6; }"
        )
        im_l.addWidget(btn_import)
        layout.addWidget(im_g)

        layout.addStretch()
        self.tabs.addTab(tab, "Export/Import")

        # Connect signals
        self.export_browser_combo.currentIndexChanged.connect(self.on_export_browser_changed)
        self.refresh_export_combo()

    def init_logs_tab(self):
        tab = QWidget()
        layout = QVBoxLayout(tab)

        toolbar = QHBoxLayout()
        self.btn_refresh_logs = QPushButton("Refresh")
        self.btn_refresh_logs.clicked.connect(self.refresh_logs)
        toolbar.addWidget(self.btn_refresh_logs)
        self.btn_clear_logs = QPushButton("Clear View")
        self.btn_clear_logs.clicked.connect(lambda: self.log_viewer.clear())
        toolbar.addWidget(self.btn_clear_logs)
        self.btn_open_log_folder = QPushButton("Open Folder")
        self.btn_open_log_folder.clicked.connect(self.open_log_folder)
        toolbar.addWidget(self.btn_open_log_folder)
        toolbar.addStretch()
        layout.addLayout(toolbar)

        self.log_viewer = QTextEdit()
        self.log_viewer.setReadOnly(True)
        self.log_viewer.setFontFamily("Consolas, 'Courier New', monospace")
        self.log_viewer.setFontPointSize(10)
        layout.addWidget(self.log_viewer)

        self.tabs.addTab(tab, "Logs")

    def _make_helpers(self, key):
        """Return toolbar layout with refresh and copy helper buttons."""
        layout = QHBoxLayout()
        rl = QPushButton("Refresh list")
        rl.clicked.connect(self.refresh_saved_backups)
        layout.addWidget(rl)
        layout.addStretch()
        return layout

    def refresh_browsers(self):
        self.browser_list.clear()
        self.res_browser_combo.clear()
        self.export_browser_combo.clear()
        self.browsers = BrowserDetection.get_installed_browsers()
        for b in self.browsers:
            display = f"{b['name']}  (v{b['version']})"
            item_widget = BrowserListItem(b, on_changed=self.on_browser_changed)
            item = QListWidgetItem()
            item.setSizeHint(item_widget.sizeHint())
            self.browser_list.addItem(item)
            self.browser_list.setItemWidget(item, item_widget)
            self.res_browser_combo.addItem(display, b)
            self.export_browser_combo.addItem(display, b)
        self.status_label.setText(f"Detected {len(self.browsers)} browser(s)")
        self.status_bar.showMessage(f"Detected {len(self.browsers)} browser(s). {self._running_count()} running.")
        self.refresh_export_combo()
        self.on_browser_changed()

    def _on_detection_done(self, browsers):
        """Slot for the _WorkerDetect thread.  Populate UI with detected browsers
        and restore the auto-refresh timer that's normally scheduled by
        refresh_browsers()."""
        self.browsers = browsers
        self.browser_list.clear()
        self.res_browser_combo.clear()
        self.export_browser_combo.clear()
        for b in browsers:
            display = f"{b['name']}  (v{b['version']})"
            item_widget = BrowserListItem(b, on_changed=self.on_browser_changed)
            item = QListWidgetItem()
            item.setSizeHint(item_widget.sizeHint())
            self.browser_list.addItem(item)
            self.browser_list.setItemWidget(item, item_widget)
            self.res_browser_combo.addItem(display, b)
            self.export_browser_combo.addItem(display, b)
        running = sum(1 for b in browsers if BrowserDetection.is_browser_running(b))
        self.status_label.setText(f"Detected {len(browsers)} browser(s)")
        self.status_bar.showMessage(f"Detected {len(browsers)} browser(s). {running} running.")
        self.refresh_export_combo()
        self.on_browser_changed()
        self.refresh_saved_backups()

    def refresh_export_combo(self):
        """Update export combo and associated profiles."""
        try:
            self.export_browser_combo.clear()
            self.export_profile_table.setRowCount(0)
            for b in self.browsers:
                display = f"{b['name']}  (v{b['version']})"
                self.export_browser_combo.addItem(display, b)
            self.on_export_browser_changed()
        except Exception:
            pass

    def on_export_browser_changed(self):
        browser = self.export_browser_combo.currentData()
        self.export_profile_table.setRowCount(0)
        if browser:
            profiles = BrowserDetection.get_browser_profiles(browser)
            for p in profiles:
                row = self.export_profile_table.rowCount()
                self.export_profile_table.insertRow(row)

                self.export_profile_table.setItem(row, 0, QTableWidgetItem(browser.get("name", "")))
                self.export_profile_table.setItem(row, 1, QTableWidgetItem(p.get("name", "")))
                self.export_profile_table.setItem(row, 2, QTableWidgetItem(p.get("display_name", "")))
                self.export_profile_table.setItem(row, 3, QTableWidgetItem(p.get("email", "")))

                # Critical Files
                full_path = p.get("full_path", "")
                critical_str = ""
                if full_path:
                    try:
                        summary = BrowserDetection.get_profile_backup_summary(full_path)
                        critical = summary.get("critical_files", [])
                        backed = sum(1 for c in critical if c["exists"])
                        total = len(critical)
                        critical_str = f"{backed}/{total}"
                    except Exception:
                        critical_str = "?"
                self.export_profile_table.setItem(row, 4, QTableWidgetItem(critical_str))

                # Est. Size
                est_size = p.get("size_mb", 0)
                self.export_profile_table.setItem(row, 5, QTableWidgetItem(f"{est_size:.1f} MB"))

                # Default
                is_default = "Yes" if p.get("is_default", False) else "No"
                self.export_profile_table.setItem(row, 6, QTableWidgetItem(is_default))

                # Store profile data
                self.export_profile_table.item(row, 0).setData(Qt.UserRole, {"browser": browser, "profile": p})

    def _running_count(self):
        n = 0
        for i in range(self.browser_list.count()):
            wi = self.browser_list.itemWidget(self.browser_list.item(i))
            if wi and wi.browser_data.get("type"):
                from core.detection import BrowserDetection as bd
                try:
                    if bd.test_browser_running(wi.browser_data):
                        wi.update_running_label(True)
                        n += 1
                except Exception:
                    pass
        return n

    def set_all_browsers(self, checked):
        for i in range(self.browser_list.count()):
            wi = self.browser_list.itemWidget(self.browser_list.item(i))
            if wi:
                wi.set_checked(checked)
        self.on_browser_changed()

    def on_browser_changed(self):
        self.profile_table.setRowCount(0)
        for i in range(self.browser_list.count()):
            item = self.browser_list.item(i)
            widget = self.browser_list.itemWidget(item)
            if not widget or not widget.is_checked():
                continue
            browser = widget.browser_data
            try:
                profiles = BrowserDetection.get_browser_profiles(browser)
                for p in profiles:
                    row = self.profile_table.rowCount()
                    self.profile_table.insertRow(row)

                    # Checkbox column
                    chk_item = QTableWidgetItem()
                    chk_item.setFlags(Qt.ItemIsUserCheckable | Qt.ItemIsEnabled)
                    chk_item.setCheckState(Qt.Checked)
                    self.profile_table.setItem(row, 0, chk_item)

                    # Browser
                    self.profile_table.setItem(row, 1, QTableWidgetItem(browser.get("name", "")))
                    # Profile
                    self.profile_table.setItem(row, 2, QTableWidgetItem(p.get("name", "")))
                    # Display Name
                    display_name = p.get("display_name", "")
                    self.profile_table.setItem(row, 3, QTableWidgetItem(display_name))
                    # Email
                    email = p.get("email", "")
                    self.profile_table.setItem(row, 4, QTableWidgetItem(email))
                    # Critical Files
                    full_path = p.get("full_path", "")
                    critical_str = ""
                    if full_path:
                        try:
                            summary = BrowserDetection.get_profile_backup_summary(full_path)
                            critical = summary.get("critical_files", [])
                            backed = sum(1 for c in critical if c["exists"])
                            total = len(critical)
                            critical_str = f"{backed}/{total}"
                        except Exception:
                            critical_str = "?"
                    self.profile_table.setItem(row, 5, QTableWidgetItem(critical_str))
                    # Est. Size
                    est_size = p.get("size_mb", 0)
                    self.profile_table.setItem(row, 6, QTableWidgetItem(f"{est_size:.1f} MB"))
                    # Default
                    is_default = "Yes" if p.get("is_default", False) else "No"
                    self.profile_table.setItem(row, 7, QTableWidgetItem(is_default))

                    # Store profile data in row
                    self.profile_table.item(row, 0).setData(Qt.UserRole, {"browser": browser, "profile": p})
            except Exception as e:
                log.error(f"Failed to load profiles for {browser.get('name')}: {e}")
        self.update_profile_count()

    def on_res_browser_changed(self):
        browser = self.res_browser_combo.currentData()
        self.res_profile_table.setRowCount(0)
        if browser:
            profiles = BrowserDetection.get_browser_profiles(browser)
            for p in profiles:
                row = self.res_profile_table.rowCount()
                self.res_profile_table.insertRow(row)

                self.res_profile_table.setItem(row, 0, QTableWidgetItem(browser.get("name", "")))
                self.res_profile_table.setItem(row, 1, QTableWidgetItem(p.get("name", "")))
                self.res_profile_table.setItem(row, 2, QTableWidgetItem(p.get("display_name", "")))
                self.res_profile_table.setItem(row, 3, QTableWidgetItem(p.get("email", "")))

                # Critical Files
                full_path = p.get("full_path", "")
                critical_str = ""
                if full_path:
                    try:
                        summary = BrowserDetection.get_profile_backup_summary(full_path)
                        critical = summary.get("critical_files", [])
                        backed = sum(1 for c in critical if c["exists"])
                        total = len(critical)
                        critical_str = f"{backed}/{total}"
                    except Exception:
                        critical_str = "?"
                self.res_profile_table.setItem(row, 4, QTableWidgetItem(critical_str))

                # Est. Size
                est_size = p.get("size_mb", 0)
                self.res_profile_table.setItem(row, 5, QTableWidgetItem(f"{est_size:.1f} MB"))

                # Default
                is_default = "Yes" if p.get("is_default", False) else "No"
                self.res_profile_table.setItem(row, 6, QTableWidgetItem(is_default))

                # Store profile data
                self.res_profile_table.item(row, 0).setData(Qt.UserRole, {"browser": browser, "profile": p})

            if self.res_profile_table.rowCount() > 0:
                self.res_profile_table.selectRow(0)

    def toggle_all_profiles(self, checked):
        self.chk_all_profiles.blockSignals(True)
        self.set_all_profiles(checked)
        self.chk_all_profiles.blockSignals(False)
        self.update_profile_count()

    def set_all_profiles(self, checked):
        for row in range(self.profile_table.rowCount()):
            item = self.profile_table.item(row, 0)
            if item:
                item.setCheckState(Qt.Checked if checked else Qt.Unchecked)
        self.update_profile_count()

    def update_profile_count(self):
        total = self.profile_table.rowCount()
        checked = 0
        for row in range(total):
            item = self.profile_table.item(row, 0)
            if item and item.checkState() == Qt.Checked:
                checked += 1
        self.profile_count_label.setText(f"{checked}/{total} profiles selected")

    def get_selected_profiles(self):
        selected = []
        for row in range(self.profile_table.rowCount()):
            chk_item = self.profile_table.item(row, 0)
            if chk_item and chk_item.checkState() == Qt.Checked:
                data = chk_item.data(Qt.UserRole)
                if data:
                    selected.append({
                        "browser": data["browser"],
                        "profile": data["profile"],
                        "item_label": f"{data['browser']['name']}/{data['profile']['name']}"
                    })
        return selected

    def browse_destination(self):
        self.browse_into(self.dest_edit, "Select Backup Destination")

    def browse_source(self):
        path = QFileDialog.getExistingDirectory(self, "Select Backup Folder (containing manifest.json)")
        if path:
            self.src_edit.setText(path)

    def browse_into(self, line_edit, title="Select Destination"):
        path = QFileDialog.getExistingDirectory(self, title)
        if path:
            line_edit.setText(path)

    def browse_export_path(self):
        path, _ = QFileDialog.getSaveFileName(self, "Save Export", "profile_backup.zip", "ZIP Files (*.zip)")
        if path:
            if not path.lower().endswith(".zip"):
                path += ".zip"
            self.export_dest_edit.setText(path)

    def browse_import_path(self):
        path, _ = QFileDialog.getOpenFileName(self, "Select Archive to Import", "", "ZIP Files (*.zip)")
        if path:
            self.import_src_edit.setText(path)

    def start_backup(self):
        selected = self.get_selected_profiles()
        dest = self.dest_edit.text().strip()

        if not selected:
            QMessageBox.warning(self, "Error", "Please select at least one browser profile.")
            return
        if not dest:
            QMessageBox.warning(self, "Error", "Please select a backup destination.")
            return
        if not os.path.exists(dest):
            try:
                os.makedirs(dest, exist_ok=True)
            except Exception as e:
                QMessageBox.critical(self, "Error", f"Cannot create destination: {e}")
                return

        exclude_dirs = config.get_default("excludeFromBackup") if self.chk_exclude_cache.isChecked() else []
        params_list = []
        for s in selected:
            profile = s["profile"]
            display = profile.get("display_name", "")
            email = profile.get("email", "")
            name_part = f"{s['browser']['name']}/{profile['name']}"
            if display and display != profile["name"]:
                name_part += f" ({display}"
                if email:
                    name_part += f" <{email}>"
                name_part += ")"
            elif email:
                name_part += f" <{email}>"
            params_list.append({
                "browser": s["browser"],
                "profile": profile,
                "destination": dest,
                "exclude_dirs": exclude_dirs,
                "log_file": log_path,
                "force": self.chk_force.isChecked(),
                "profile_name": name_part,
            })

        self.btn_backup.setEnabled(False)
        self.btn_cancel.setEnabled(True)
        self.backup_progress.setRange(0, len(params_list))
        self.backup_progress.setValue(0)

        self.worker = Worker("backup", params_list)
        self.worker.progress.connect(self.status_label.setText)
        self.worker.progress_value.connect(self.update_progress)
        self.worker.finished.connect(self.on_backup_finished)
        self.worker.start()

    def cancel_task(self):
        if self.worker and self.worker.isRunning():
            self.worker.cancel()
            self.status_label.setText("Cancelling...")

    @Slot(int, int)
    def update_progress(self, current, total):
        self.backup_progress.setMaximum(total)
        self.backup_progress.setValue(current)

    @Slot(dict)
    def on_backup_finished(self, result):
        self.btn_backup.setEnabled(True)
        self.btn_cancel.setEnabled(False)
        if result.get("cancelled"):
            self.status_label.setText("Backup cancelled")
            self.status_bar.showMessage("Backup cancelled")
            QMessageBox.warning(self, "Cancelled", "Backup cancelled by user.")
        elif result["success"]:
            self.status_label.setText("Backup completed")
            self.status_bar.showMessage("Backup completed successfully")
            QMessageBox.information(self, "Success", result["message"])
            self.backup_progress.setValue(self.backup_progress.maximum())
            self.refresh_saved_backups()
        else:
            self.status_label.setText("Backup failed")
            self.status_bar.showMessage("Backup failed")
            QMessageBox.critical(self, "Error", f"Backup failed: {result['message']}")
            self.backup_progress.setValue(0)

    def start_restore(self):
        browser = self.res_browser_combo.currentData()
        rows = self.res_profile_table.selectionModel().selectedRows() if self.res_profile_table.selectionModel() else []
        src = self.src_edit.text().strip()

        if not browser:
            QMessageBox.warning(self, "Error", "Please select a browser.")
            return
        if not rows:
            QMessageBox.warning(self, "Error", "Please select a profile to restore to.")
            return
        if not src:
            QMessageBox.warning(self, "Error", "Please select a backup folder.")
            return
        if not os.path.exists(os.path.join(src, "manifest.json")):
            QMessageBox.warning(self, "Error", "Selected folder does not contain a valid backup (missing manifest.json).")
            return

        row = rows[0].row()
        item = self.res_profile_table.item(row, 0)
        profile = item.data(Qt.UserRole) if item else None
        if not profile:
            QMessageBox.warning(self, "Error", "Selected profile has no data. Please re-select.")
            return

        params = {
            "browser": browser,
            "profile": profile,
            "backup_path": src,
            "log_file": log_path,
            "force": self.res_chk_force.isChecked(),
            "create_rollback": self.res_chk_rollback.isChecked(),
        }

        self.btn_restore.setEnabled(False)
        restore_label = f"Restoring {browser['name']}/{profile['name']}"
        self.status_label.setText(restore_label)
        self.status_bar.showMessage(restore_label)

        self.worker = Worker("restore", [params])
        self.worker.progress.connect(self.status_label.setText)
        self.worker.finished.connect(self.on_restore_finished)
        self.worker.start()

    @Slot(dict)
    def on_restore_finished(self, result):
        self.btn_restore.setEnabled(True)
        if result["success"]:
            QMessageBox.information(self, "Success", result["message"])
            self.status_label.setText("Restore completed")
            self.status_bar.showMessage("Restore completed")
        else:
            QMessageBox.critical(self, "Error", f"Restore failed: {result['message']}")
            self.status_label.setText("Restore failed")
            self.status_bar.showMessage("Restore failed")

    def refresh_logs(self):
        try:
            if os.path.exists(log_path):
                with open(log_path, "r", encoding="utf-8") as f:
                    self.log_viewer.setText(f.read())
                self.log_viewer.moveCursor(self.log_viewer.textCursor().End)
            else:
                self.log_viewer.setText("No log file found.")
        except Exception as e:
            self.log_viewer.setText(f"Could not read logs: {e}")

    def open_log_folder(self):
        try:
            folder = os.path.dirname(log_path)
            os.startfile(folder)
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Cannot open folder: {e}")

    def refresh_saved_backups(self):
        """Refresh the verify/backup lists."""
        dest = os.path.expandvars(config_manager.get_default("backupDestination"))
        from core.backup import list_backups as _list
        try:
            backups = _list(dest)
        except Exception:
            backups = {}

        for list_widget in [self.verify_list, self.backup_list_a, self.backup_list_b]:
            list_widget.clear()
            for browser_name, folders in sorted(backups.items()):
                for folder in folders:
                    item = QListWidgetItem(f"{browser_name} | {folder['path']}")
                    item.setData(Qt.UserRole, folder['path'])
                    list_widget.addItem(item)

    def delete_selected_backup(self):
        item = self.backup_list_a.currentItem()
        if not item:
            QMessageBox.warning(self, "Error", "Please select a backup from the LEFT list to delete.")
            return
        path = item.data(Qt.UserRole)
        confirm = QMessageBox.question(
            self, "Confirm Delete",
            f"Delete backup folder:\n{path}\n\nThis cannot be undone.",
            QMessageBox.Yes | QMessageBox.No
        )
        if confirm == QMessageBox.Yes:
            import shutil
            try:
                shutil.rmtree(path)
                self.compare_output.append(f"[DELETED] {path}")
                self.refresh_saved_backups()
            except Exception as e:
                QMessageBox.critical(self, "Error", f"Could not delete: {e}")

    def compare_two_backups(self):
        a = self.backup_list_a.currentItem()
        b = self.backup_list_b.currentItem()
        if not a or not b:
            QMessageBox.warning(self, "Error", "Please select one backup in each list (left=oldest, right=newest).")
            return
        ap = a.data(Qt.UserRole)
        bp = b.data(Qt.UserRole)
        try:
            from core.backup import BackupEngine
            comparison = BackupEngine.compare_backups(ap, bp)
            self.compare_output.setText(self._format_comparison(comparison))
        except Exception as e:
            self.compare_output.setText(f"Comparison failed: {e}")

    def _format_comparison(self, c):
        lines = []
        lines.append("=" * 78)
        lines.append("BACKUP COMPARISON")
        lines.append("=" * 78)
        lines.append(f"  OLD:  {c.get('old_path')}")
        lines.append(f"  NEW:  {c.get('new_path')}")
        lines.append(f"  Files in OLD only:    {len(c.get('files_only_in_old', []))}")
        lines.append(f"  Files in NEW only:    {len(c.get('files_only_in_new', []))}")
        lines.append(f"  Files modified:       {len(c.get('files_modified', []))}")
        lines.append(f"  Files identical:      {len(c.get('files_identical', []))}")
        lines.append("=" * 78)
        if c.get('files_only_in_old'):
            lines.append("\n[REMOVED FILES (in OLD not in NEW)]")
            for f in sorted(c['files_only_in_old'])[:50]:
                lines.append(f"  - {f}")
            if len(c['files_only_in_old']) > 50:
                lines.append(f"  ... and {len(c['files_only_in_old']) - 50} more")
        if c.get('files_only_in_new'):
            lines.append("\n[NEW FILES (in NEW not in OLD)]")
            for f in sorted(c['files_only_in_new'])[:50]:
                lines.append(f"  + {f}")
            if len(c['files_only_in_new']) > 50:
                lines.append(f"  ... and {len(c['files_only_in_new']) - 50} more")
        if c.get('files_modified'):
            lines.append("\n[MODIFIED FILES]")
            for entry in c['files_modified'][:50]:
                lines.append(f"  * {entry.get('path', '?')}")
            if len(c['files_modified']) > 50:
                lines.append(f"  ... and {len(c['files_modified']) - 50} more")
        return "\n".join(lines)

    def verify_selected(self):
        item = self.verify_list.currentItem()
        if not item:
            QMessageBox.warning(self, "Error", "Please select a backup to verify.")
            return
        path = item.data(Qt.UserRole)
        self.verify_results.append(f"\n--- Verifying {path} ---")
        self.status_bar.showMessage(f"Verifying {path}...")
        self.worker = Worker("verify", [{"backup_path": path, "log_file": log_path, "item_label": path}])
        self.worker.progress.connect(lambda msg: self.verify_results.append(msg))
        self.worker.log_message.connect(self.verify_results.append)
        self.worker.finished.connect(self.on_verify_finished)
        self.worker.start()

    @Slot(dict)
    def on_verify_finished(self, result):
        if result.get("success"):
            self.verify_results.append(f"[OK] {result.get('message', 'Verification passed')}")
            self.status_bar.showMessage("Verification passed")
        else:
            self.verify_results.append(f"[FAIL] {result.get('message', 'Verification failed')}")
            self.status_bar.showMessage("Verification failed")

    def apply_schedule(self):
        if not self.schedule_enabled.isChecked():
            self.stop_schedule()
            return
        interval_min = self.schedule_interval.value()
        dest = self.schedule_dest_edit.text().strip()
        if not dest:
            QMessageBox.warning(self, "Error", "Please specify a destination folder for scheduled backups.")
            return
        if self.backup_schedule_timer is None:
            self.backup_schedule_timer = QTimer(self)
            self.backup_schedule_timer.timeout.connect(self._run_scheduled_backup)
        self.backup_schedule_timer.start(interval_min * 60 * 1000)
        self.schedule_status.setText(
            f"<b style='color:#16a085;'>Schedule active</b> — every {interval_min} minute(s) -> {dest}"
        )
        self.status_bar.showMessage(f"Backup schedule active (every {interval_min} min)")

    def stop_schedule(self):
        if self.backup_schedule_timer:
            self.backup_schedule_timer.stop()
        self.schedule_status.setText("No schedule is currently active.")
        self.schedule_enabled.setChecked(False)
        self.status_bar.showMessage("Schedule stopped")

    def _run_scheduled_backup(self):
        """Run a backup of every discovered browser profile to the configured destination."""
        dest = self.schedule_dest_edit.text().strip()
        if not dest:
            self.schedule_status.setText("Schedule active but missing destination.")
            return
        os.makedirs(dest, exist_ok=True)
        browsers = BrowserDetection.get_installed_browsers()
        params_list = []
        for browser in browsers:
            try:
                profiles = BrowserDetection.get_browser_profiles(browser)
                for p in profiles:
                    params_list.append({
                        "browser": browser,
                        "profile": p,
                        "destination": dest,
                        "exclude_dirs": config.get_default("excludeFromBackup"),
                        "log_file": log_path,
                        "force": False,
                        "profile_name": f"{browser['name']}/{p['name']}",
                    })
            except Exception as e:
                log.error(f"Scheduled backup failed building profile list: {e}")
        if not params_list:
            return
        self._running_scheduled_job = True
        self.status_bar.showMessage(f"Running scheduled backup ({len(params_list)} items)...")
        self.worker = Worker("backup", params_list)
        self.worker.progress.connect(self.status_bar.showMessage)
        self.worker.finished.connect(self._on_scheduled_backup_done)
        self.worker.start()

    def _on_scheduled_backup_done(self, result):
        self.refresh_saved_backups()
        if result["success"]:
            self.status_bar.showMessage("Scheduled backup completed")
        else:
            self.status_bar.showMessage(f"Scheduled backup issues: {result.get('message', '?')}")

    def export_profile(self):
        # Get selected row from table
        selected_rows = self.export_profile_table.selectionModel().selectedRows()
        out_path = self.export_dest_edit.text().strip()
        if not selected_rows:
            QMessageBox.warning(self, "Error", "Please select a profile to export.")
            return
        if not out_path:
            QMessageBox.warning(self, "Error", "Please specify an output path (.zip).")
            return
        row = selected_rows[0].row()
        item = self.export_profile_table.item(row, 0)
        data = item.data(Qt.UserRole)
        try:
            from core.backup import BackupEngine
            ok, msg = BackupEngine.export_profile_zip(
                data["browser"],
                data["profile"],
                out_path,
                log_file=log_path,
            )
            if ok:
                QMessageBox.information(self, "Success", f"Profile exported to:\n{out_path}")
            else:
                QMessageBox.critical(self, "Error", f"Export failed: {msg}")
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Export exception: {e}")

    def import_profile(self):
        in_path = self.import_src_edit.text().strip()
        if not in_path or not os.path.exists(in_path):
            QMessageBox.warning(self, "Error", "Please select a valid .zip archive to import.")
            return
        try:
            from core.backup import BackupEngine
            result = BackupEngine.import_profile_zip(in_path, log_file=log_path)
            if result.get("success"):
                QMessageBox.information(
                    self, "Success",
                    f"Profile imported into:\n{result.get('dest_path')}\n\n"
                    f"Browser: {result.get('browser_name')}\n"
                    f"Profile: {result.get('profile_name')}"
                )
            else:
                QMessageBox.critical(self, "Error", f"Import failed: {result.get('message')}")
        except Exception as e:
            QMessageBox.critical(self, "Error", f"Import exception: {e}")


def parse_cli_args():
    p = argparse.ArgumentParser(description="Universal Browser Backup", add_help=True)
    p.add_argument("--no-gui", action="store_true", help="Disable GUI mode (CLI only)")
    p.add_argument("--list", action="store_true", help="List installed browsers and exit")
    p.add_argument("--backup", action="store_true", help="Run a backup from CLI")
    p.add_argument("--restore", action="store_true", help="Run a restore from CLI")
    p.add_argument("--browser", type=str, default="", help="Browser name filter")
    p.add_argument("--profile", type=str, default="Default", help="Profile name")
    p.add_argument("--destination", type=str, default="", help="Destination folder")
    p.add_argument("--source", type=str, default="", help="Backup source folder")
    p.add_argument("--all-profiles", action="store_true", help="Backup every profile")
    p.add_argument("--exclude-cache", action="store_true", help="Skip cache folders")
    p.add_argument("--force", action="store_true", help="Force kill browser process")
    p.add_argument("--logs", action="store_true", help="Show log file path and exit")
    p.add_argument("--verify", action="store_true", help="Verify backup from CLI")
    p.add_argument("--version", action="store_true", help="Print version and exit")
    return p.parse_args()


def cli_main(args):
    if args.version:
        print("Universal Browser Backup v2.1.1")
        return 0
    if args.logs:
        print(f"Log file: {get_log_path()}")
        return 0
    if args.list:
        browsers = BrowserDetection.get_installed_browsers()
        if not browsers:
            print("No browsers found.")
            return 0
        print("Installed Browsers:")
        print("-" * 70)
        for b in browsers:
            print(f"  {b['name']} (v{b['version']}) - {b.get('type', '?')}")
            try:
                profiles = BrowserDetection.get_browser_profiles(b)
                for p in profiles:
                    default = " (default)" if p.get("is_default") else ""
                    name_part = p['name']
                    if p.get("display_name") and p["display_name"] != p["name"]:
                        name_part += f" - {p['display_name']}"
                    if p.get("email"):
                        name_part += f" <{p['email']}>"
                    cf = p.get("critical_files")
                    cf_str = f" | critical: {cf}" if cf is not None else ""
                    print(f"      - {name_part} [{p['size_mb']:.1f} MB]{default}{cf_str}")
            except Exception as e:
                print(f"      [profiles unavailable: {e}]")
            print()
        return 0
    if args.backup:
        if not args.destination:
            print("ERROR: --destination is required for --backup", file=sys.stderr)
            return 3
        browsers = BrowserDetection.get_installed_browsers()
        if args.browser:
            browser = next((b for b in browsers if args.browser.lower() in b["name"].lower()), None)
        else:
            browser = browsers[0] if browsers else None
        if not browser:
            print(f"ERROR: browser '{args.browser}' not found", file=sys.stderr)
            return 3
        os.makedirs(args.destination, exist_ok=True)
        exclude_dirs = config.get_default("excludeFromBackup") if args.exclude_cache else []
        if args.all_profiles:
            profiles = BrowserDetection.get_browser_profiles(browser)
        else:
            profiles = [{"name": args.profile, "size_mb": 0, "is_default": True, "path": ""}]
        results = []
        for p in profiles:
            r = BackupEngine.run_backup(
                browser=browser,
                profile=p,
                destination=args.destination,
                exclude_dirs=exclude_dirs,
                log_file=log_path,
                force=args.force,
                profile_name=p["name"],
            )
            print(f"  {p['name']}: {'OK' if r.get('success') else r.get('message', 'failed')}")
            results.append(r.get("success", False))
        return 0 if all(results) else 5
    if args.restore:
        if not args.source:
            print("ERROR: --source is required for --restore", file=sys.stderr)
            return 3
        browsers = BrowserDetection.get_installed_browsers()
        if args.browser:
            browser = next((b for b in browsers if args.browser.lower() in b["name"].lower()), None)
        else:
            browser = browsers[0] if browsers else None
        if not browser:
            print(f"ERROR: browser '{args.browser}' not found", file=sys.stderr)
            return 3
        profiles = BrowserDetection.get_browser_profiles(browser)
        profile = next((p for p in profiles if p["name"] == args.profile), profiles[0] if profiles else None)
        if not profile:
            print("ERROR: no profile found", file=sys.stderr)
            return 3
        r = RestoreEngine.run_restore(
            browser=browser,
            profile=profile,
            backup_path=args.source,
            log_file=log_path,
            force=args.force,
        )
        print(r.get("message", "done"))
        return 0 if r.get("success") else 5
    if args.verify:
        if not args.source:
            print("ERROR: --source is required for --verify", file=sys.stderr)
            return 3
        r = BackupEngine.verify_backup(backup_path=args.source, log_file=log_path)
        print(r.get("message", "done"))
        return 0 if r.get("success") else 5
    return None


def main():
    args = parse_cli_args()
    if not args.no_gui or any([args.list, args.backup, args.restore, args.verify, args.logs, args.version]):
        rc = cli_main(args)
        if rc is not None:
            print(f"\nLog file: {get_log_path()}")
            sys.exit(rc)

    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setApplicationName("Universal Browser Backup")
    app.setOrganizationName("Universal Browser Backup")
    app.setApplicationVersion("2.1.1")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


def _open_main_window(g):
    hi = g["QApplication"]
    QMainWindow = g["QMainWindow"]
    sys_argv = hi
    sys_argv = sys.argv
    app = hi(sys_argv)
    app.setStyle("Fusion")
    app.setApplicationName("Universal Browser Backup")
    app.setOrganizationName("Universal Browser Backup")
    app.setApplicationVersion("2.1.1")
    MainWindow = g["MainWindow"]
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
