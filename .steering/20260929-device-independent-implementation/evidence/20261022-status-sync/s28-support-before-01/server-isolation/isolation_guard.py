"""S20 trusted-code test guard; not an OS sandbox or a native-code boundary.

Install before adding snapshot/site-packages to sys.path. The enclosing Codex
filesystem sandbox remains independent. Native libraries may perform operations
without Python audit events, so provenance and final artifacts are also checked.
"""
import fcntl
import errno
import json
import os
import posix
from pathlib import Path
import socket
import subprocess
import sqlite3
import _sqlite3
import sys
import threading
import urllib.parse
import weakref


class IsolationViolation(RuntimeError):
    pass


class Guard:
    def __init__(self, runtime, *, allow_missing_ffprobe_version=False, allow_loopback_listener=False,
                 evidence_directory=None):
        self.runtime = Path(runtime).resolve(strict=True)
        evidence = self.runtime if evidence_directory is None else Path(evidence_directory)
        if evidence.is_symlink() or not evidence.resolve(strict=True).is_relative_to(self.runtime):
            raise IsolationViolation("Audit evidence must remain inside the runtime")
        self.log = (evidence / "audit.jsonl").open("x", encoding="utf-8")
        self.counts = {}
        self.denials = []
        self.connections = weakref.WeakSet()
        self.connection_events = []
        self.connection_observers = []
        self._base_connection = sqlite3.Connection
        self._base_connect = sqlite3.connect
        self._base_open = os.open
        self._open_context = threading.local()
        self.allow_missing_ffprobe_version = allow_missing_ffprobe_version
        self.missing_ffprobe = self.runtime / "disabled-ffprobe"
        self._base_popen = subprocess.Popen
        self._popen_init_code = subprocess.Popen.__init__.__code__
        self._popen_devnull_code = subprocess.Popen._get_devnull.__code__
        self.allow_loopback_listener = allow_loopback_listener
        self.listener_bind_count = 0

    def note(self, event, detail):
        self.counts[event] = self.counts.get(event, 0) + 1
        self.log.write(json.dumps({"event": event, "detail": detail}, sort_keys=True) + "\n")
        self.log.flush()

    def deny(self, event, detail):
        self.denials.append({"event": event, "detail": detail})
        self.note("denied:" + event, detail)
        raise IsolationViolation(event + ": " + str(detail))

    def fd_path(self, fd):
        if sys.platform != "darwin":
            self.deny("fd-path", "This reviewed runner is macOS-only")
        # macOS F_GETPATH obtains the current path of an already-open descriptor.
        raw = fcntl.fcntl(fd, 50, bytes(1024))
        return Path(os.fsdecode(raw.split(b"\0", 1)[0]))

    def path(self, value, dir_fd=None):
        if isinstance(value, int):
            return self.fd_path(value).resolve()
        path = Path(os.fsdecode(value))
        if not path.is_absolute():
            parent = self.fd_path(dir_fd) if dir_fd not in (None, -1) else Path.cwd()
            path = parent / path
        return path.resolve()

    def require_runtime(self, value, event, dir_fd=None):
        try:
            canonical = self.path(value, dir_fd)
        except (OSError, ValueError, TypeError) as error:
            self.deny(event, {"unresolved_path": str(value), "reason": type(error).__name__})
        if not canonical.is_relative_to(self.runtime):
            self.deny(event, {"outside_runtime": str(canonical)})
        if canonical == self.missing_ffprobe and event not in {"environment-path"}:
            self.deny(event, {"reserved_absent_executable": str(canonical)})
        return canonical

    def missing_version_argv(self, argv):
        return (self.allow_missing_ffprobe_version
                and argv == [str(self.missing_ffprobe), "-version"]
                and not os.path.lexists(self.missing_ffprobe))

    def devnull_for_missing_version(self):
        """Allow stdlib Popen's device FD only for the reviewed exact invocation."""
        frame = sys._getframe(1)
        saw_devnull = False
        try:
            while frame is not None:
                if frame.f_code is self._popen_devnull_code:
                    saw_devnull = True
                if frame.f_code is self._popen_init_code:
                    values = frame.f_locals
                    return (saw_devnull and self.missing_version_argv(values.get("args"))
                            and values.get("shell") is False and values.get("cwd") is None
                            and values.get("env") is None and values.get("pass_fds") == ())
                frame = frame.f_back
            return False
        finally:
            del frame

    def database_path(self, database):
        name = os.fsdecode(database)
        if name == ":memory:":
            return name
        if name.startswith("file:"):
            uri = urllib.parse.urlsplit(name)
            if uri.netloc or uri.fragment:
                self.deny("sqlite-uri", "authority/fragment is not permitted")
            query = urllib.parse.parse_qs(uri.query, strict_parsing=True)
            if any(key not in {"mode", "immutable"} for key in query):
                self.deny("sqlite-uri", "unreviewed URI option")
            if "mode" in query and query["mode"] != ["ro"]:
                self.deny("sqlite-uri", "only read-only file URI is reviewed")
            if "immutable" in query and query["immutable"] != ["1"]:
                self.deny("sqlite-uri", "invalid immutable option")
            name = urllib.parse.unquote(uri.path)
        if not name:
            self.deny("sqlite-connect", "empty temporary database name")
        path = self.require_runtime(name, "sqlite-connect")
        for suffix in ("", "-wal", "-shm", "-journal"):
            candidate = Path(str(path) + suffix)
            if candidate.is_symlink():
                self.deny("sqlite-sidecar", str(candidate))
            self.require_runtime(candidate, "sqlite-sidecar")
        return str(path)

    def authorizer(self, action, arg1, arg2, database, origin):
        if action == sqlite3.SQLITE_ATTACH:
            self.note("denied:sqlite-extra-file", {"operation": "ATTACH or VACUUM INTO", "path": arg1})
            return sqlite3.SQLITE_DENY
        if action == sqlite3.SQLITE_PRAGMA and str(arg1).lower() in {"temp_store_directory", "data_store_directory"}:
            self.note("denied:sqlite-path-pragma", {"pragma": arg1})
            return sqlite3.SQLITE_DENY
        if action == sqlite3.SQLITE_FUNCTION and str(arg2).lower() == "load_extension":
            self.note("denied:sqlite-extension", {})
            return sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_OK

    def install(self):
        guard = self
        base_connection = self._base_connection

        def open_with_directory(path, flags, mode=0o777, *, dir_fd=None):
            # CPython's open audit event omits dir_fd. Resolve the actual parent
            # before the syscall and carry that resolution to the same thread's
            # event. Absolute paths intentionally ignore dir_fd, as POSIX does.
            native_path = os.fspath(path)
            writable = flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND)
            exempt_devnull = (native_path == "/dev/null" and
                flags & os.O_ACCMODE == os.O_RDWR and
                flags & ~(os.O_RDWR | os.O_CLOEXEC) == 0 and guard.devnull_for_missing_version())
            canonical = (guard.require_runtime(native_path, "open", dir_fd)
                         if writable and not exempt_devnull else None)
            stack = getattr(guard._open_context, "stack", None)
            if stack is None:
                stack = guard._open_context.stack = []
            stack.append((native_path, canonical, dir_fd))
            try:
                return guard._base_open(native_path, flags, mode, dir_fd=dir_fd)
            finally:
                stack.pop()

        # Both names initially reference the same native function. Keep direct
        # posix.open calls under the same check; do not change FD ownership.
        os.open = open_with_directory
        posix.open = open_with_directory

        class GuardedConnection(base_connection):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self._s20_thread = threading.get_ident()
                base_connection.set_authorizer(self, guard.authorizer)
                guard.connections.add(self)
                identifier = id(self)
                guard.connection_events.append({"event": "opened", "id": identifier, "thread": self._s20_thread})
                # A GC event is recorded separately from an explicit close. It is
                # not an in-process proof that every native FD is gone.
                guard.connection_observers.append(weakref.ref(self, lambda _ref, identifier=identifier:
                    guard.connection_events.append({"event": "garbage_collected", "id": identifier})))

            def set_authorizer(self, callback):
                guard.deny("sqlite-authorizer-replacement", "guard cannot be removed")

            def enable_load_extension(self, enabled):
                guard.deny("sqlite-extension", "extensions are not permitted")

            def load_extension(self, *args, **kwargs):
                guard.deny("sqlite-extension", "extensions are not permitted")

            def close(self):
                super().close()
                guard.connections.discard(self)
                guard.connection_events.append({"event": "closed", "id": id(self)})

        self.guarded_connection = GuardedConnection

        def connect(database, *args, **kwargs):
            guard.database_path(database)
            # CPython positional order: timeout, detect_types, isolation_level,
            # check_same_thread, factory. Unreviewed factories could omit guard.
            if len(args) > 4 or ("factory" in kwargs and kwargs["factory"] is not GuardedConnection):
                guard.deny("sqlite-factory", "custom connection factory")
            kwargs["factory"] = GuardedConnection
            return guard._base_connect(database, *args, **kwargs)

        sqlite3.connect = connect
        sqlite3.dbapi2.connect = connect
        _sqlite3.connect = connect
        sqlite3.Connection = GuardedConnection
        sqlite3.dbapi2.Connection = GuardedConnection
        _sqlite3.Connection = GuardedConnection

        class ObservedMissingExecutable(guard._base_popen):
            def __init__(self, *args, **kwargs):
                expected = {"cwd": None, "shell": False, "start_new_session": True,
                    "stdin": subprocess.DEVNULL, "stdout": subprocess.PIPE, "stderr": subprocess.PIPE,
                    "close_fds": True, "pass_fds": (), "env": None}
                if len(args) != 1 or not guard.missing_version_argv(args[0]) or kwargs != expected:
                    guard.deny("subprocess.Popen", "only the exact missing ffprobe -version attempt is reviewed")
                try:
                    super().__init__(*args, **kwargs)
                except FileNotFoundError as error:
                    # This is the actual OS error, observed then re-raised intact.
                    if error.errno != errno.ENOENT or error.filename != str(guard.missing_ffprobe):
                        raise
                    guard.note("observed:missing-ffprobe-ENOENT", {"executable": error.filename, "errno": error.errno})
                    raise
                else:
                    # The reserved path must remain absent. If native/outside
                    # interference ever defeats that assumption, stop only this
                    # just-created child and fail rather than run backend work.
                    self.kill()
                    self.wait(timeout=5)
                    guard.deny("unexpected-executable", "reserved missing path unexpectedly launched")

        if self.allow_missing_ffprobe_version:
            subprocess.Popen = ObservedMissingExecutable
        sys.addaudithook(self.audit)

    def audit(self, event, args):
        if event == "open":
            value, mode, flags = args
            writable = (isinstance(mode, str) and any(c in mode for c in "wax+")) or (
                isinstance(flags, int) and flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND))
            if writable:
                if (value == "/dev/null" and mode is None and isinstance(flags, int)
                        and flags & os.O_ACCMODE == os.O_RDWR
                        and flags & ~(os.O_RDWR | os.O_CLOEXEC) == 0
                        and self.devnull_for_missing_version()):
                    self.note("allowed:popen-devnull", {"path": value, "flags": flags})
                    return
                stack = getattr(self._open_context, "stack", [])
                context = stack[-1] if stack and stack[-1][0] == value else None
                path = context[1] if context is not None and context[1] is not None else self.require_runtime(value, event)
                detail = {"path": str(path), "mode": mode, "flags": flags}
                if context is not None and context[2] is not None:
                    detail["dir_fd"] = context[2]
                    detail["absolute_path_ignores_dir_fd"] = Path(os.fsdecode(value)).is_absolute()
                self.note(event, detail)
        elif event in {"os.rename", "os.link"}:
            source, destination = args[:2]
            source_fd, destination_fd = args[2:4]
            self.require_runtime(source, event, source_fd)
            path = self.require_runtime(destination, event, destination_fd)
            self.note(event, {"source": str(source), "destination": str(path)})
        elif event == "os.symlink":
            source, destination, dir_fd = args
            target = self.require_runtime(destination, event, dir_fd)
            resolved_source = Path(os.fsdecode(source))
            if not resolved_source.is_absolute():
                resolved_source = target.parent / resolved_source
            self.require_runtime(resolved_source, event)
            self.note(event, {"source": str(resolved_source), "destination": str(target)})
        elif event in {"os.remove", "os.rmdir", "os.mkdir", "os.chmod", "os.chown", "os.utime"}:
            # These audit events end with their optional dir_fd argument.
            path = self.require_runtime(args[0], event, args[-1])
            self.note(event, {"path": str(path)})
        elif event in {"os.truncate", "os.chdir"}:
            path = self.require_runtime(args[0], event)
            self.note(event, {"path": str(path)})
        elif event.startswith("shutil.") and event in {"shutil.copyfile", "shutil.copymode", "shutil.copystat", "shutil.copytree", "shutil.move"}:
            self.require_runtime(args[1], event)
        elif event == "shutil.rmtree":
            self.require_runtime(args[0], event, args[1] if len(args) > 1 else None)
        elif event == "subprocess.Popen":
            executable, argv, cwd, env = args
            if not (executable == str(self.missing_ffprobe) and self.missing_version_argv(argv)
                    and cwd is None and env is None):
                self.deny(event, "subprocess is not permitted")
            self.note("allowed:missing-ffprobe-attempt", {"executable": executable, "argv": argv})
        elif event.startswith("subprocess.") or event in {"os.system", "os.fork", "os.forkpty", "os.posix_spawn", "os.exec", "os.spawn", "pty.spawn"}:
            self.deny(event, "subprocess/fork/spawn is not permitted")
        elif event == "socket.__new__":
            _socket, family, kind, protocol = args
            permitted_family = family == socket.AF_UNIX or (self.allow_loopback_listener and family == socket.AF_INET)
            if not permitted_family or (kind & 15) != socket.SOCK_STREAM:
                self.deny(event, {"family": family, "type": kind, "protocol": protocol})
        elif event == "socket.bind" and self.allow_loopback_listener:
            target, address = args
            if target.family != socket.AF_INET or address != ("127.0.0.1", 0) or self.listener_bind_count:
                self.deny(event, "only one IPv4 loopback bind to an OS-selected port is reviewed")
            self.listener_bind_count += 1
            self.note("allowed:loopback-bind", {"address": address})
        elif event in {"socket.bind", "socket.connect", "socket.sendto", "socket.getaddrinfo", "socket.gethostbyname", "socket.gethostbyaddr"}:
            self.deny(event, "no listener or external connection in pytest checkpoint")
        elif event == "sqlite3.connect":
            path = self.database_path(args[0])
            self.note(event, {"database": path})
        elif event == "sqlite3.connect/handle":
            if not isinstance(args[0], self.guarded_connection):
                self.deny(event, "unguarded native connection constructor")
        elif event in {"sqlite3.enable_load_extension", "sqlite3.load_extension"}:
            self.deny(event, "native extension loading is not permitted")
        elif event == "os.putenv":
            key, value = (os.fsdecode(item) for item in args)
            if key in {"MEDIA_ROOT", "DATABASE_PATH", "LUT_PATH", "USER_LUT_ROOT", "BUILT_IN_PRESET_ROOT",
                       "APPLE_LOG_DETECTOR_ROOT", "TMPDIR", "TMP", "TEMP", "SQLITE_TMPDIR", "XDG_CACHE_HOME"}:
                self.require_runtime(value, "environment-path")

    def finish(self):
        # sqlite Connection.__exit__ commits/rolls back but does not close.
        # Close only this thread's survivors. Tests retain SQLite's real default
        # check_same_thread behavior; a TestClient worker's survivor must remain
        # "not explicitly closed" until its owner/GC/process exit is observed.
        survivors = list(self.connections)
        before = len(survivors)
        foreign_thread = []
        close_failures = []
        for connection in survivors:
            if connection._s20_thread != threading.get_ident():
                foreign_thread.append({"id": id(connection), "owner_thread": connection._s20_thread})
                continue
            try:
                connection.close()
            except sqlite3.Error as error:
                close_failures.append({"id": id(connection), "error": str(error)})
        self.log.flush()
        return {"counts": self.counts, "denials": self.denials,
                "sqlite_connections_alive_before_explicit_close": before,
                "sqlite_connections_alive_after_explicit_close": len(self.connections),
                "foreign_thread_connections_not_explicitly_closed": foreign_thread,
                "sqlite_close_failures": close_failures,
                "sqlite_connection_events": self.connection_events,
                "limitation": "Python audit/connection guard is not an OS/native-code sandbox"}
