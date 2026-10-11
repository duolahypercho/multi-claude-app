#!/usr/bin/env python3
"""Exercise real native management commands in disposable, non-integrated roots."""
import json
import hashlib
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
BINARY = PROJECT / "build/multi-claude-app"


class ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture_temp = tempfile.TemporaryDirectory(prefix="multi-claude-native-fixture-")
        cls.fixture = Path(cls.fixture_temp.name) / "Claude"
        subprocess.run(["xcrun", "clang", str(PROJECT / "tests/fixture-native.c"), "-o", str(cls.fixture)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixture_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="multi-claude-tests-")
        self.base = Path(self.temp.name)
        self.root = self.base / "State with spaces"
        self.apps = self.base / "Applications"
        self.app = self.base / "Claude.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        executable = self.app / "Contents/MacOS/Claude"
        executable.write_bytes(self.fixture.read_bytes())
        executable.chmod(0o755)
        (self.app / "Contents/Resources").mkdir()
        (self.app / "Contents/Resources/Assets.car").write_bytes(b"original icon catalog")
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.anthropic.claudefordesktop",
                          "CFBundleExecutable": "Claude", "CFBundleName": "Claude", "CFBundleIconName": "Claude",
                          "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "CFBundleURLTypes": [
                              {"CFBundleURLSchemes": ["claude"]},
                              {"CFBundleURLSchemes": ["msauth.com.anthropic.claudefordesktop"]}]}, stream)
        self.invoke("setup", "--count", "2", "--no-integration", "--app", str(self.app), "--applications", str(self.apps))

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, *args, ok=True, input=None):
        result = subprocess.run([str(BINARY), "--root", str(self.root), *args],
                                text=True, input=input, capture_output=True, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def config(self):
        return json.loads((self.root / "config.json").read_text())

    def test_original_profile_and_repeat_setup(self):
        c = self.config()
        self.assertEqual(c["profiles"][0]["userDataDir"], "")
        self.assertFalse(c["integrationEnabled"])
        self.assertEqual(c["loginRoutingMode"], "native")
        self.assertTrue(Path(c["managerPath"]).exists())
        marker = Path(c["profiles"][1]["userDataDir"]) / "existing-account"
        marker.write_text("preserve this account")
        self.invoke("setup", "--count", "1", "--no-integration")
        self.assertEqual(len(self.config()["profiles"]), 2)
        self.assertEqual(marker.read_text(), "preserve this account")
        self.assertEqual((self.root / "config.json").stat().st_mode & 0o777, 0o600)

    def test_tagged_icon_belongs_to_the_native_account_app(self):
        self.invoke("rename", "2", "work@example.com")
        p = self.config()["profiles"][1]
        bundle = Path(p["launcherPath"])
        with (bundle / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        self.assertFalse(info["LSUIElement"])
        self.assertTrue(info["MultiClaudeNative"])
        self.assertEqual(info["CFBundleName"], "Claude")  # Electron helper discovery
        self.assertEqual(info["CFBundleExecutable"], "MultiClaudeNative")
        self.assertEqual(info["MultiClaudeNativeExecutable"], "Claude")
        self.assertEqual(info["CFBundleIdentifier"], "local.multi-claude-app.profile2")
        self.assertEqual(info["CFBundleDisplayName"], "Claude work@example.com")
        self.assertNotIn("CFBundleIconName", info)
        self.assertIn("CFBundleURLTypes", info)
        self.assertFalse((bundle / "Contents/Resources/Assets.car").exists())
        self.assertTrue((bundle / "Contents/MacOS/Claude").exists())
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True, capture_output=True)
        svg = (bundle / "Contents/Resources/ProfileIcon.svg").read_text()
        self.assertIn(">W2</text>", svg)
        self.assertIn('fill="#D97757"', svg)
        with (Path(self.config()["managerPath"]) / "Contents/Info.plist").open("rb") as stream:
            manager = plistlib.load(stream)
        self.assertTrue(manager["LSUIElement"])

    def test_native_bootstrap_replaces_its_pid_and_selects_only_its_storage(self):
        for p in self.config()["profiles"]:
            executable = Path(p["launcherPath"]) / "Contents/MacOS/MultiClaudeNative"
            env = dict(os.environ, CLAUDE_CONFIG_DIR="wrong-account", CLAUDE_USER_DATA_DIR="wrong-storage",
                       CLAUDE_CDP_AUTH="invalid-token", ELECTRON_RUN_AS_NODE="1")
            process = subprocess.Popen([str(executable)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output, errors = process.communicate(timeout=30)
            self.assertEqual(process.returncode, 0, errors.decode())
            fields = output.decode().split("\0")
            self.assertEqual(int(fields[0]), process.pid)
            self.assertEqual(fields[1], str(Path(p["launcherPath"]) / "Contents/MacOS/Claude"))
            data = p["userDataDir"] or str(Path.home() / "Library/Application Support/Claude")
            self.assertEqual(fields[2], "--user-data-dir=" + data)
            self.assertEqual(fields[3], p["codeConfigDir"])
            self.assertEqual(fields[4:7], ["", "", ""])
            self.assertEqual(fields[7], "1")

    def test_native_copy_install_and_repair_leave_original_bundle_untouched(self):
        original = {str(p.relative_to(self.app)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in self.app.rglob("*") if p.is_file()}
        account = Path(self.config()["profiles"][1]["launcherPath"])
        inode = account.stat().st_ino
        self.invoke("setup", "--no-integration")
        self.assertEqual(account.stat().st_ino, inode)  # no replacement on repeat setup
        self.invoke("icon", "2", "teal")
        after = {str(p.relative_to(self.app)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in self.app.rglob("*") if p.is_file()}
        self.assertEqual(original, after)

    def test_ten_accounts_have_distinct_native_app_ids_and_original_data(self):
        self.invoke("setup", "--count", "10", "--no-integration")
        profiles = self.config()["profiles"]
        self.assertEqual(len(profiles), 10)
        self.assertEqual(len({p["launcherPath"] for p in profiles}), 10)
        ids = set()
        for p in profiles:
            with (Path(p["launcherPath"]) / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            ids.add(info["CFBundleIdentifier"])
            self.assertTrue(info["MultiClaudeNative"])
        self.assertEqual(len(ids), 10)

    def test_login_modes_and_old_config_migrate_without_losing_data(self):
        c = self.config()
        p = c["profiles"][1]
        marker = Path(p["userDataDir"]) / "session"
        marker.write_text("keep")
        c.pop("loginRoutingMode")
        c.pop("managerPath")
        (self.root / "config.json").write_text(json.dumps(c))
        self.invoke("list")
        self.invoke("setup", "--no-integration")
        self.assertEqual(self.config()["loginRoutingMode"], "native")
        self.invoke("login-routing", "chooser")
        self.assertEqual(self.config()["loginRoutingMode"], "chooser")
        self.invoke("login-routing", "native")
        original = (self.root / "config.json").read_bytes()
        self.invoke("login-routing", "invalid", ok=False)
        self.assertEqual((self.root / "config.json").read_bytes(), original)
        self.assertEqual(marker.read_text(), "keep")

    def test_manager_collision_is_preserved(self):
        manager = Path(self.config()["managerPath"])
        with (manager / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "unrelated.manager"}, stream)
        marker = manager / "unrelated.txt"
        marker.write_text("leave alone")
        original = (self.root / "config.json").read_bytes()
        self.invoke("setup", "--no-integration", ok=False)
        self.assertEqual(marker.read_text(), "leave alone")
        self.assertEqual((self.root / "config.json").read_bytes(), original)

    def test_rename_color_keeps_data(self):
        before = self.config()["profiles"][1]
        marker = Path(before["userDataDir"]) / "session"
        marker.write_text("keep")
        self.invoke("rename", "2", "Research & Development")
        self.invoke("icon", "2", "teal")
        after = self.config()["profiles"][1]
        self.assertEqual(after["userDataDir"], before["userDataDir"])
        self.assertEqual(after["codeConfigDir"], before["codeConfigDir"])
        self.assertEqual(marker.read_text(), "keep")
        self.assertFalse(Path(before["launcherPath"]).exists())
        self.assertTrue(Path(after["launcherPath"]).exists())
        self.assertEqual(after["iconColor"], "teal")

    def test_remove_restore_and_never_reuse_numbers(self):
        p = self.config()["profiles"][1]
        marker = Path(p["userDataDir"]) / "login"
        marker.write_text("do not delete")
        self.invoke("remove", "2")
        self.assertFalse(Path(p["launcherPath"]).exists())
        self.assertEqual(marker.read_text(), "do not delete")
        self.invoke("add", "--name", "Work")
        self.assertEqual(self.config()["profiles"][-1]["id"], "3")
        self.invoke("restore", "2")
        self.assertEqual(marker.read_text(), "do not delete")
        self.assertTrue(Path(p["launcherPath"]).exists())

    def test_name_validation_and_collisions_leave_configuration(self):
        original = (self.root / "config.json").read_bytes()
        for name in ["../Bad", "claude", "Primary", "CLAUDE PRIMARY", "Bad\nName", "Trailing."]:
            self.invoke("rename", "2", name, ok=False)
            self.assertEqual((self.root / "config.json").read_bytes(), original)
        unrelated = self.apps / "Claude Other.app"
        unrelated.mkdir()
        (unrelated / "keep.txt").write_text("unrelated")
        self.invoke("add", "--name", "Other", ok=False)
        self.assertEqual((unrelated / "keep.txt").read_text(), "unrelated")
        self.assertEqual((self.root / "config.json").read_bytes(), original)

    def test_uninstall_preserves_data_and_reinstall_restores(self):
        p = self.config()["profiles"][1]
        marker = Path(p["userDataDir"]) / "data"
        marker.write_text("saved")
        self.invoke("uninstall")
        self.assertFalse(Path(p["launcherPath"]).exists())
        self.assertEqual(marker.read_text(), "saved")
        self.invoke("setup", "--count", "2", "--no-integration")
        self.assertTrue(Path(p["launcherPath"]).exists())
        self.assertEqual(marker.read_text(), "saved")

    def test_malformed_links_are_rejected_without_logging_secrets(self):
        for url in ["https://example.com/?code=TOP_SECRET", "claude://user@claude.ai/?code=TOP_SECRET",
                    "claude://claude.ai:8080/?code=TOP_SECRET", "claude://claude.ai/?code=TOP_SECRET\n"]:
            result = self.invoke("deliver", "2", input=url, ok=False)
            self.assertIn("Invalid Claude link", result.stderr)
            self.assertNotIn("TOP_SECRET", result.stderr + result.stdout)
        result = self.invoke("deliver", "2", input="claude://claude.ai/magic-link?code=TOP_SECRET", ok=False)
        self.assertIn("Open the selected profile", result.stderr)
        self.assertNotIn("TOP_SECRET", result.stderr + result.stdout)

    def test_corrupt_configuration_is_never_reset(self):
        path = self.root / "config.json"
        path.write_text("broken config")
        self.invoke("setup", "--no-integration", ok=False)
        self.assertEqual(path.read_text(), "broken config")

    def test_redirected_profile_data_is_rejected(self):
        p = self.config()["profiles"][1]
        desktop = Path(p["userDataDir"])
        desktop.rmdir()
        outside = self.base / "outside"
        outside.mkdir()
        marker = outside / "account"
        marker.write_text("untouched")
        desktop.symlink_to(outside, target_is_directory=True)
        self.invoke("setup", "--no-integration", ok=False)
        self.assertEqual(marker.read_text(), "untouched")

    def test_invalid_cli_options_and_missing_profiles(self):
        original = (self.root / "config.json").read_bytes()
        for args in [("setup", "--count", "0"), ("add", "--color", "red"),
                     ("add", "--count", "101"), ("rename", "999", "Missing"),
                     ("setup", "--unknown"), ("setup", "--count")]:
            self.invoke(*args, ok=False)
            self.assertEqual((self.root / "config.json").read_bytes(), original)


if __name__ == "__main__":
    if not BINARY.exists():
        raise SystemExit("Build first: sh scripts/build.sh")
    unittest.main(verbosity=2)
