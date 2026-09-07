#!/usr/bin/env python3
"""Local synthetic tests: no real Codex, scheduler, SSH or remote commands.

All subprocesses receive a fresh environment and disposable HOME. Optional
root-only cases change ownership exclusively inside that disposable fixture.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
JOB = "4242"
MOCK = r'''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
Path(os.environ["MOCK_RECORD"]).write_text(json.dumps({
    "argv": sys.argv[1:], "pid": os.getpid(),
    "env": {k: os.environ.get(k) for k in ("HOME", "CODEX_HOME", "TMPDIR",
                                         "CODEX_INSTALL_DIR", "PATH")}
}))
if os.environ.get("MOCK_WAIT") == "1":
    while True: time.sleep(1)
sys.stdout.buffer.write(bytes([0, 255, 13, 10]) + b"no-newline")
sys.stderr.buffer.write(b"separate-stderr")
sys.exit(int(os.environ.get("MOCK_EXIT", "0")))
'''
QUEUE = r'''#!/usr/bin/python3
import os, pwd, sys
if os.environ.get("MOCK_QUEUE_ERROR"): sys.exit(7)
for arg in sys.argv:
    if arg == "--format=%T": print(os.environ.get("MOCK_JOB_STATE", "RUNNING"))
    if arg == "--format=%u": print(os.environ.get("MOCK_OWNER", pwd.getpwuid(os.getuid()).pw_name))
'''
SRUN = r'''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
Path(os.environ["MOCK_SRUN_RECORD"]).write_text(json.dumps(args))
start = args.index("env")
os.environ["SLURM_JOB_ID"] = "4242"
os.environ["SLURM_STEP_ID"] = "7"
os.execv("/usr/bin/env", args[start:])
'''


class Fixture:
    def __init__(self):
        # Keep the Unix socket name below macOS/Linux path-length limits.
        self.temp = tempfile.TemporaryDirectory(prefix="codex-backend-", dir="/tmp")
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.state_base = self.root / "state"
        self.state = self.state_base / "codex-apocrita"
        self.tmp = self.root / "tmp"
        self.listener = self.home / ".codex"
        self.bin = self.root / "bin"
        self.runtime = self.home / ".local/share/codex-apocrita/current/remote"
        for path in (self.home / ".local/bin", self.state, self.tmp, self.bin,
                     self.runtime, self.listener / "app-server-control"):
            path.mkdir(parents=True, mode=0o700)
        for name in ("codex-dispatch", "codex-slurm", "codex-step-entry"):
            target = self.runtime / name
            target.write_bytes((ROOT / "remote" / name).read_bytes())
            target.chmod(0o700)
        self.upstream = self.home / ".local/bin/codex-direct"
        self.write_program(self.upstream, MOCK)
        self.write_program(self.bin / "squeue", QUEUE)
        self.write_program(self.bin / "srun", SRUN)
        if sys.platform != "linux":
            # Only the fixtures run on macOS: the installed backend is Linux.
            # Linux exercises real GNU readlink; other hosts emulate GNU -m.
            self.write_program(self.bin / "readlink", '''#!/usr/bin/python3
import os, sys
assert sys.argv[1:3] == ["-m", "--"] and len(sys.argv) == 4
print(os.path.realpath(sys.argv[3]))
''')
        for name in ("ssh", "sbatch", "scancel", "codex"):
            self.write_program(self.bin / name, "#!/bin/sh\nexit 99\n")
        (self.state / "job-id").write_text(JOB + "\n")
        # These strings are fictional sentinels, not user credentials or logs.
        for relative in ("auth.json", "config.toml", "sessions/example.jsonl",
                         "tmp/arg0/live-helper/codex-linux-sandbox"):
            path = self.listener / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fictional preserved listener state\n")
        self.record = self.root / "invocation.json"
        self.srun_record = self.root / "srun.json"
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home),
            "TMPDIR": str(self.tmp), "XDG_STATE_HOME": str(self.state_base),
            "MOCK_RECORD": str(self.record), "MOCK_SRUN_RECORD": str(self.srun_record),
        }
        self.sock = None
        self.bind_socket()

    @staticmethod
    def write_program(path, text):
        text = text.replace("#!/usr/bin/python3", "#!" + sys.executable, 1)
        path.write_text(text)
        path.chmod(0o700)

    def bind_socket(self):
        self.socket_path = self.listener / "app-server-control/app-server-control.sock"
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(str(self.socket_path))
        self.sock.listen(1)

    def command(self, args, entry=False):
        if entry:
            return ["/bin/bash", str(self.runtime / "codex-step-entry"),
                    JOB, str(self.state), *args]
        return ["/bin/bash", str(self.runtime / "codex-dispatch"), *args]

    def run(self, args, entry=False):
        self.record.unlink(missing_ok=True)
        self.srun_record.unlink(missing_ok=True)
        env = dict(self.env)
        if entry:
            env.update(SLURM_JOB_ID=JOB, SLURM_STEP_ID="7")
        return subprocess.run(self.command(args, entry), env=env,
                              capture_output=True, timeout=10)

    def invocation(self):
        return json.loads(self.record.read_text())

    def listener_snapshot(self):
        return {str(p.relative_to(self.listener)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.listener.rglob("*") if p.is_file()}

    def close(self):
        if self.sock:
            self.sock.close()
        self.temp.cleanup()


class BackendIsolationTests(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()
        self.addCleanup(self.f.close)

    def reject(self, result, message=None):
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.f.record.exists(), "Upstream must not run on rejection")
        if message:
            self.assertIn(message.encode(), result.stderr)

    def test_scripts_have_valid_bash_syntax(self):
        for name in ("codex-dispatch", "codex-slurm", "codex-step-entry"):
            subprocess.run(["/bin/bash", "-n", str(self.f.runtime / name)], check=True,
                           env=self.f.env, capture_output=True)

    def test_version_isolated_empty_private_home_preserves_streams(self):
        before = self.f.listener_snapshot()
        self.f.env["CODEX_HOME"] = str(self.f.listener)
        self.f.env["MOCK_EXIT"] = "23"
        result = self.f.run(["--version"])
        self.assertEqual(result.returncode, 23)
        self.assertEqual(result.stdout, bytes([0, 255, 13, 10]) + b"no-newline")
        self.assertEqual(result.stderr, b"separate-stderr")
        invocation = self.f.invocation()
        isolated = Path(invocation["env"]["CODEX_HOME"])
        self.assertEqual(isolated, self.f.state / "version-probe-home")
        self.assertEqual(stat.S_IMODE(isolated.stat().st_mode), 0o700)
        self.assertEqual(list(isolated.iterdir()), [])
        self.assertEqual(invocation["argv"], ["--version"])
        self.assertEqual(self.f.listener_snapshot(), before)
        self.assertFalse(self.f.srun_record.exists())

    def test_version_reuses_only_its_helper_directory(self):
        self.assertEqual(self.f.run(["--version"]).returncode, 0)
        private = self.f.state / "version-probe-home"
        (private / "tmp").mkdir()
        self.assertEqual(self.f.run(["--version"]).returncode, 0)
        (private / "config.toml").write_text("unexpected")
        self.reject(self.f.run(["--version"]), "Unexpected content")

    def test_version_state_symlink_rejected(self):
        self.f.state.rename(self.f.state.with_name("saved-state"))
        self.f.state.symlink_to(self.f.state.with_name("saved-state"), target_is_directory=True)
        self.reject(self.f.run(["--version"]), "symlink")

    def test_version_private_home_dangling_symlink_rejected(self):
        (self.f.state / "version-probe-home").symlink_to(self.f.root / "absent")
        self.reject(self.f.run(["--version"]), "symlink")

    def test_version_helper_symlink_rejected(self):
        private = self.f.state / "version-probe-home"
        private.mkdir()
        (private / "tmp").symlink_to(self.f.tmp, target_is_directory=True)
        self.reject(self.f.run(["--version"]), "Unexpected content")

    def test_version_relative_state_rejected(self):
        self.f.env["XDG_STATE_HOME"] = "relative-state"
        self.reject(self.f.run(["--version"]), "absolute")

    def test_version_home_inside_tmp_rejected(self):
        self.f.env["TMPDIR"] = str(self.f.state_base)
        self.reject(self.f.run(["--version"]), "outside")

    def test_version_root_tmp_rejected(self):
        self.f.env["TMPDIR"] = "/"
        self.reject(self.f.run(["--version"]), "outside")

    def test_version_default_state_location(self):
        del self.f.env["XDG_STATE_HOME"]
        self.assertEqual(self.f.run(["--version"]).returncode, 0)
        self.assertEqual(Path(self.f.invocation()["env"]["CODEX_HOME"]),
                         self.f.home / ".local/state/codex-apocrita/version-probe-home")

    def test_other_dispatch_arguments_and_home_unchanged(self):
        self.f.env["CODEX_HOME"] = str(self.f.listener)
        for args in ([], ["-V"], ["--version", "extra"], ["-c", "setting=true", "--version"],
                     ["review", "space text", "line\nnext", 'quote"back\\slash']):
            with self.subTest(args=args):
                self.assertEqual(self.f.run(args).returncode, 0)
                invocation = self.f.invocation()
                self.assertEqual(invocation["argv"], args)
                self.assertEqual(invocation["env"]["CODEX_HOME"], str(self.f.listener))
                self.assertFalse(self.f.srun_record.exists())

    def test_default_proxy_routes_real_socket_into_unique_homes(self):
        before = self.f.listener_snapshot()
        homes = set()
        for _ in range(2):
            result = self.f.run(["app-server", "proxy"])
            self.assertEqual(result.returncode, 0, result.stderr)
            invocation = self.f.invocation()
            self.assertEqual(invocation["argv"],
                             ["app-server", "proxy", "--sock", str(self.f.socket_path)])
            private = Path(invocation["env"]["CODEX_HOME"])
            self.assertEqual(private.parent, self.f.state / "proxy-homes/job-4242")
            self.assertEqual(stat.S_IMODE(private.stat().st_mode), 0o700)
            self.assertEqual(list(private.iterdir()), [])
            self.assertEqual(invocation["env"]["HOME"], str(self.f.home))
            self.assertNotEqual(private, Path(invocation["env"]["TMPDIR"]))
            homes.add(private)
        self.assertEqual(len(homes), 2)
        self.assertEqual(self.f.listener_snapshot(), before)
        srun = json.loads(self.f.srun_record.read_text())
        for flag in ("--jobid=4242", "--overlap", "--unbuffered", "--ntasks=1"):
            self.assertIn(flag, srun)
        self.assertNotIn("--pty", srun)
        self.assertFalse(any(a.startswith(("--cpus-per-task", "--mem", "--gpus")) for a in srun))

    def test_proxy_custom_listener_home_uses_its_real_socket(self):
        self.f.sock.close()
        old = self.f.listener
        custom = self.f.root / "custom-listener"
        old.rename(custom)
        (custom / "app-server-control/app-server-control.sock").unlink()
        self.f.listener = custom
        self.f.bind_socket()
        self.f.env["CODEX_HOME"] = str(custom)
        before = self.f.listener_snapshot()
        result = self.f.run(["app-server", "proxy"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.f.invocation()["argv"][-1], str(self.f.socket_path))
        self.assertEqual(self.f.listener_snapshot(), before)

    def test_proxy_streams_and_nonzero_exit_preserved(self):
        self.f.env["MOCK_EXIT"] = "17"
        result = self.f.run(["app-server", "proxy"])
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout, bytes([0, 255, 13, 10]) + b"no-newline")
        self.assertEqual(result.stderr, b"separate-stderr")

    def test_unreviewed_proxy_arguments_rejected(self):
        for args in (["app-server", "proxy", "--sock", "/fictional/other.sock"],
                     ["-c", "setting=true", "app-server", "proxy"],
                     ["app-server", "proxy", "--help"]):
            with self.subTest(args=args):
                self.reject(self.f.run(args), "default app-server proxy")

    def test_listener_and_other_app_server_arguments_unchanged(self):
        self.f.env["CODEX_HOME"] = str(self.f.listener)
        before = self.f.listener_snapshot()
        for args in (["app-server", "--listen", "unix://"],
                     ["-c", "setting=true", "app-server", "--listen", "stdio"],
                     ["app-server", "--help"]):
            with self.subTest(args=args):
                self.assertEqual(self.f.run(args).returncode, 0)
                invocation = self.f.invocation()
                self.assertEqual(invocation["argv"], args)
                self.assertEqual(invocation["env"]["CODEX_HOME"], str(self.f.listener))
        self.assertEqual(self.f.listener_snapshot(), before)
        self.assertFalse((self.f.state / "proxy-homes").exists())

    def test_missing_listener_socket_rejected(self):
        self.f.socket_path.unlink()
        self.reject(self.f.run(["app-server", "proxy"]), "socket")

    def test_regular_file_socket_rejected(self):
        self.f.socket_path.unlink()
        self.f.socket_path.write_text("not a socket")
        self.reject(self.f.run(["app-server", "proxy"]), "socket")

    def test_socket_symlink_rejected(self):
        destination = self.f.socket_path.with_name("saved.sock")
        self.f.socket_path.rename(destination)
        self.f.socket_path.symlink_to(destination)
        self.reject(self.f.run(["app-server", "proxy"]), "socket")

    def test_control_directory_symlink_rejected(self):
        control = self.f.socket_path.parent
        saved = control.with_name("saved-control")
        control.rename(saved)
        control.symlink_to(saved, target_is_directory=True)
        self.reject(self.f.run(["app-server", "proxy"]), "socket")

    def test_listener_home_symlink_rejected(self):
        saved = self.f.listener.with_name("saved-listener")
        self.f.listener.rename(saved)
        self.f.listener.symlink_to(saved, target_is_directory=True)
        self.reject(self.f.run(["app-server", "proxy"]), "Listener home")

    def test_proxy_state_symlink_rejected(self):
        root = self.f.state / "proxy-homes"
        root.symlink_to(self.f.root / "not-created", target_is_directory=True)
        self.reject(self.f.run(["app-server", "proxy"]), "symlink")

    def test_proxy_home_under_tmp_rejected_after_canonicalization(self):
        self.f.env["TMPDIR"] = str(self.f.state)
        self.reject(self.f.run(["app-server", "proxy"], entry=True), "outside")

    def test_proxy_root_tmp_rejected(self):
        self.f.env["TMPDIR"] = "/"
        self.reject(self.f.run(["app-server", "proxy"], entry=True), "outside")

    def test_shared_tmp_symlink_rejected_before_mode_changes(self):
        target = self.f.root / "untouched"
        target.mkdir(mode=0o755)
        (self.f.state / "tmp").symlink_to(target, target_is_directory=True)
        self.reject(self.f.run(["app-server", "proxy"]), "symlink")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755)
        self.assertEqual(list(target.iterdir()), [])
        self.assertFalse(self.f.srun_record.exists())

    def test_proxy_similarly_prefixed_tmp_sibling_is_allowed(self):
        self.f.env["TMPDIR"] = str(self.f.state / "proxy")
        result = self.f.run(["app-server", "proxy"], entry=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_scheduler_failures_do_not_run_upstream(self):
        for setting in ({"MOCK_QUEUE_ERROR": "1"}, {"MOCK_JOB_STATE": "PENDING"},
                        {"MOCK_OWNER": "fictional-other-user"}):
            with self.subTest(setting=setting):
                self.f.env.update(setting)
                self.reject(self.f.run(["app-server", "proxy"]))
                self.assertFalse(self.f.srun_record.exists())
                for key in setting:
                    del self.f.env[key]

    def test_step_job_identity_guard(self):
        env = dict(self.f.env, SLURM_JOB_ID="9999", SLURM_STEP_ID="7")
        result = subprocess.run(self.f.command(["app-server", "proxy"], entry=True),
                                env=env, capture_output=True, timeout=10)
        self.reject(result, "recorded Slurm job")

    def test_proxy_exec_retains_pid_and_sigterm(self):
        env = dict(self.f.env, MOCK_WAIT="1", SLURM_JOB_ID=JOB, SLURM_STEP_ID="7")
        proc = subprocess.Popen(self.f.command(["app-server", "proxy"], entry=True),
                                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not self.f.record.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.f.record.exists())
            self.assertEqual(self.f.invocation()["pid"], proc.pid)
            proc.send_signal(signal.SIGTERM)
            proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, -signal.SIGTERM)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

    @unittest.skipUnless(os.geteuid() == 0, "Foreign-owner fixture requires local root")
    def test_foreign_owned_listener_socket_rejected(self):
        os.chown(self.f.socket_path, 65534, 65534)
        self.reject(self.f.run(["app-server", "proxy"]), "socket")

    @unittest.skipUnless(os.geteuid() == 0, "Foreign-owner fixture requires local root")
    def test_foreign_owned_listener_home_rejected(self):
        os.chown(self.f.listener, 65534, 65534)
        self.reject(self.f.run(["app-server", "proxy"]), "Listener home")

    @unittest.skipUnless(os.geteuid() == 0, "Foreign-owner fixture requires local root")
    def test_foreign_owned_version_state_rejected(self):
        os.chown(self.f.state, 65534, 65534)
        self.reject(self.f.run(["--version"]), "user-owned")


if __name__ == "__main__":
    if any(os.environ.get(k) for k in ("SLURM_JOB_ID", "SLURM_JOBID", "SLURM_STEP_ID")):
        raise SystemExit("These fixtures must not be run inside a Slurm job.")
    unittest.main(verbosity=2)
