"""Regression checks for the Codex migration; only temporary fixtures are written."""

import importlib.util
import json
import re
import shlex
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".codex/hooks/branch_version_hook.py"
SYNC = ROOT / ".agents/skills/sync-version/scripts/sync_version.py"
spec = importlib.util.spec_from_file_location("branch_version_hook", HOOK)
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class BranchHookTests(unittest.TestCase):
    def run_hook(self, payload):
        result = subprocess.run(
            [sys.executable, str(HOOK)], input=json.dumps(payload),
            text=True, capture_output=True, check=True,
        )
        return json.loads(result.stdout) if result.stdout else None

    def test_shipping_prefixes_under_codex_namespace(self):
        for branch, level in (("codex/feat/subtitles", "minor"),
                              ("codex/fix-empty-folder", "patch"),
                              ("hotfix/crash", "patch")):
            with self.subTest(branch=branch):
                message = hook.build_message(branch, ROOT)
                self.assertIn(f"**{level}**", message)
                self.assertIn(".agents/skills/sync-version/", message)

    def test_housekeeping_and_release_branches_are_quiet(self):
        for branch in ("codex/chore/imports", "codex/docs-guide", "ci/checks",
                       "codex/release-1.4.0", "fix/version-drift"):
            with self.subTest(branch=branch):
                self.assertIsNone(hook.build_message(branch, ROOT))

    def test_unknown_prefix_does_not_guess(self):
        self.assertIn("no obvious bump level", hook.build_message("codex/new-idea", ROOT))

    def test_shell_payloads_and_force_variants(self):
        for tool, key, command in (
            ("Bash", "command", "git switch -c codex/feat/subtitles"),
            ("PowerShell", "command", "git checkout -B codex/fix-empty-folder"),
            ("exec_command", "cmd", "git switch -C codex/fix-empty-folder"),
        ):
            with self.subTest(tool=tool):
                output = self.run_hook({"tool_name": tool, "cwd": str(ROOT / "scripts"),
                                        "tool_input": {key: command}})
                self.assertEqual(output["hookSpecificOutput"]["hookEventName"], "PreToolUse")
                self.assertIn(f"Current version: `{hook.current_version(ROOT)}`", output["hookSpecificOutput"]["additionalContext"])

    def test_unrelated_and_malformed_payloads_are_quiet(self):
        for payload in (None, [], {}, {"tool_name": "apply_patch"},
                        {"tool_name": "Bash", "tool_input": []},
                        {"tool_name": "Bash", "tool_input": {"command": 7}},
                        {"tool_name": "Bash", "tool_input": {"command": "git status"}}):
            with self.subTest(payload=payload):
                self.assertIsNone(self.run_hook(payload))
        result = subprocess.run([sys.executable, str(HOOK)], input="not json",
                                text=True, capture_output=True)
        self.assertEqual((result.returncode, result.stdout), (0, ""))

    def test_configured_launcher_works_from_subdirectory(self):
        config = json.loads((ROOT / ".codex/hooks.json").read_text(encoding="utf-8"))
        group = config["hooks"]["PreToolUse"][0]
        self.assertIsNotNone(re.fullmatch(group["matcher"], "Bash"))
        command = shlex.split(group["hooks"][0]["commandWindows"])
        command[0] = sys.executable
        result = subprocess.run(command, cwd=ROOT / "scripts", text=True,
                                input=json.dumps({"tool_name": "Bash", "cwd": str(ROOT / "scripts"),
                                                  "tool_input": {"command": "git switch -c codex/feat/subtitles"}}),
                                capture_output=True, check=True)
        self.assertIn("hookSpecificOutput", json.loads(result.stdout))


class VersionSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.files = {
            "pubspec.yaml": "version: 0.9.0+1\nmsix_config:\n  msix_version: 0.9.0.0\n",
            "lib/widgets/settings/settings_screen.dart": "const _appVersion = '0.9.0+1';\n",
            "scripts/inno_setup.iss": '#define MyAppVersion "0.9.0"\n',
            "AGENTS.md": "Current app version: `0.9.0+1`.\n",
        }
        for rel, content in self.files.items():
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")

    def run_sync(self, *args):
        return subprocess.run([sys.executable, str(SYNC), *args], cwd=self.root / "scripts",
                              text=True, capture_output=True)

    def test_show_and_dry_run_do_not_write(self):
        self.assertEqual(self.run_sync("--show").stdout.strip(), "0.9.0+1")
        result = self.run_sync("--dry-run", "minor")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.10.0+2", result.stdout)
        for rel, original in self.files.items():
            self.assertEqual((self.root / rel).read_text(encoding="utf-8"), original)

    def test_explicit_target_updates_all_copies_and_is_idempotent(self):
        result = self.run_sync("1.2.0+5")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("version: 1.2.0+5", (self.root / "pubspec.yaml").read_text())
        self.assertIn("msix_version: 1.2.0.0", (self.root / "pubspec.yaml").read_text())
        self.assertIn("'1.2.0+5'", (self.root / "lib/widgets/settings/settings_screen.dart").read_text())
        self.assertIn('"1.2.0"', (self.root / "scripts/inno_setup.iss").read_text())
        self.assertIn("`1.2.0+5`", (self.root / "AGENTS.md").read_text())
        self.assertIn("Updated 0 file(s)", self.run_sync("1.2.0+5").stdout)

    def test_missing_migrated_target_fails(self):
        (self.root / "AGENTS.md").unlink()
        result = self.run_sync("--dry-run", "patch")
        self.assertEqual(result.returncode, 2)
        self.assertIn("AGENTS.md", result.stdout)

    def test_invalid_version_does_not_write(self):
        self.assertNotEqual(self.run_sync("invalid").returncode, 0)
        self.assertEqual((self.root / "pubspec.yaml").read_text(), self.files["pubspec.yaml"])


class InstructionTests(unittest.TestCase):
    def test_project_config_enables_hook_layer(self):
        config = tomllib.loads((ROOT / ".codex/config.toml").read_text(encoding="utf-8"))
        self.assertTrue(config["features"]["hooks"])

    def test_root_instructions_fit_default_limit(self):
        self.assertLess(len((ROOT / "AGENTS.md").read_bytes()), 32 * 1024)
        self.assertFalse((ROOT / "CLAUDE.md").exists())

    def test_migrated_instruction_links_resolve(self):
        for rel in ("AGENTS.md", "docs/architecture/agent-invariants.md"):
            path = ROOT / rel
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
                if target.startswith(("https://", "#")):
                    continue
                with self.subTest(document=rel, target=target):
                    self.assertTrue((path.parent / target.split("#", 1)[0]).exists())


if __name__ == "__main__":
    unittest.main()
