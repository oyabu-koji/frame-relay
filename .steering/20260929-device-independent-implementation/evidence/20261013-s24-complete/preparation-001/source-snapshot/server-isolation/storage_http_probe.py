"""Separate stdlib host client; only the exact ready loopback origin is reachable.

Never imports backend, emits credentials, follows redirects, or uses proxies.
"""
import argparse
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import stat
import sys
import time
from urllib.parse import urlencode, urlsplit
from uuid import uuid4


def local_lifecycle():
    spec = importlib.util.spec_from_file_location("listener_lifecycle", Path(__file__).with_name("listener_lifecycle.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--listener-pid", type=int, required=True)
    args = parser.parse_args()
    if not (sys.flags.isolated and sys.flags.no_site and sys.dont_write_bytecode):
        raise SystemExit("Require -I -B -S")
    life = local_lifecycle()
    config = life.read_json(args.config)
    runtime = Path(config["runtime"])
    directory = life.phase_directory(runtime, config)
    life.verify_sources(config, Path(__file__).parent)
    ready = life.checked_ready(directory / "listener-ready.json", config, args.listener_pid)
    phase = config["storage_phase"]
    credentials_path = directory / "storage-http-env.json"
    if stat.S_IMODE(credentials_path.lstat().st_mode) != 0o600:
        raise RuntimeError("Credential file mode mismatch")
    credentials = life.read_json(credentials_path)
    if any(credentials.get(key) != value for key, value in (
            ("run_identity", config["run_identity"]), ("storage_phase", phase),
            ("listener_pid", args.listener_pid), ("url", ready["url"]))):
        raise RuntimeError("Credential/ready identity mismatch")
    token = credentials["bootstrap_token"]
    address = ("127.0.0.1", urlsplit(ready["url"]).port)
    state_path = runtime / "storage-client-state.json"
    started = time.monotonic()
    deadline = min(started + 150, ready["deadline_monotonic"] - 30)
    report = {"run_identity": config["run_identity"], "storage_phase": phase,
        "listener_pid": args.listener_pid, "client_pid": os.getpid(), "passed": False,
        "cases": [], "request_counts": {}, "all_connections_closed": False,
        "proxy_enabled": False, "redirect_following": False, "backend_imported": False}
    all_connections = []

    def audit(event, values):
        if event == "socket.__new__":
            if values[1] != socket.AF_INET or values[2] != socket.SOCK_STREAM:
                raise RuntimeError("Client permits IPv4 stream sockets only")
        elif event == "socket.connect":
            if values[1] != address:
                raise RuntimeError("Client destination differs from ready loopback origin")
        elif event in {"socket.bind", "socket.sendto", "socket.getaddrinfo", "socket.gethostbyname",
                       "socket.gethostbyaddr"} or event.startswith("subprocess.") or event in {
                       "os.system", "os.fork", "os.forkpty", "os.posix_spawn", "os.exec", "os.spawn"}:
            raise RuntimeError("Client network/subprocess operation not permitted")
    sys.addaudithook(audit)

    class ExactConnection(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout)
            self.sock.connect(address)

    def request(case, method, path, *, payload=None, body=None, binding=None,
                secret=None, bearer=None, expected=(200,), extra=None):
        if time.monotonic() >= deadline:
            raise TimeoutError("HTTP probe deadline exceeded")
        if not path.startswith("/frame-relay/v1/") or "?" in path or "#" in path:
            raise RuntimeError("Unreviewed request path")
        if binding is not None:
            path += "?" + urlencode(binding)
        headers = {"Authorization": "Bearer " + (token if bearer is None else bearer),
                   "Connection": "close"}
        if secret is not None:
            headers["X-FrameRelay-Registration-Secret"] = secret
        if payload is not None:
            body = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        if extra:
            headers.update(extra)
        connection = ExactConnection(address[0], address[1], timeout=10)
        all_connections.append(connection)
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            raw = response.read(65537)
            if len(raw) > 65536 or response.status not in expected or 300 <= response.status < 400:
                raise RuntimeError("Unexpected HTTP status, redirect, or response size")
            value = json.loads(raw)
            key = case + ":" + str(response.status)
            report["request_counts"][key] = report["request_counts"].get(key, 0) + 1
            return value
        finally:
            connection.close()

    def passed(name):
        if name in report["cases"]:
            raise RuntimeError("Duplicate case record")
        report["cases"].append(name)

    def check_proof(value, binding, expected_binding):
        proof = value.get("evidence")
        if (value.get("binding") != expected_binding or value.get("status") != "completed" or
                value.get("failure_code") is not None or not isinstance(proof, dict) or
                proof.get("schema_version") != "fr-final-read-v1" or
                proof.get("method") != "final_destination_read_back" or
                proof.get("committed") is not True or proof.get("final_save_completed") is not True or
                proof.get("byte_count") != binding["byte_count"] or proof.get("sha256") != binding["sha256"] or
                not proof.get("evidence_id") or not proof.get("observed_at")):
            raise RuntimeError("Final proof differs from exact upload contract")

    try:
        caps = request("capabilities", "GET", "/frame-relay/v1/capabilities")
        if caps.get("destination_id") != ready["destination_id"]:
            raise RuntimeError("Destination mismatch")
        passed("capabilities_exact_destination")
        if phase == 1:
            secret = secrets.token_hex(32)
            registration_request = {"destination_id": ready["destination_id"], "operation_id": str(uuid4())}
            receipt = request("register", "POST", "/frame-relay/v1/registrations",
                              payload=registration_request, secret=secret)
            if any(receipt.get(k) != v for k, v in registration_request.items()):
                raise RuntimeError("Registration binding mismatch")
            if request("register_replay", "POST", "/frame-relay/v1/registrations",
                       payload=registration_request, secret=secret) != receipt:
                raise RuntimeError("Registration replay changed identity")
            passed("registration_exact_replay")
            total = 2 * 8388608 + 257
            data = life.synthetic_bytes(0, total)
            binding = {"destination_id": receipt["destination_id"],
                "registration_id": receipt["registration_id"], "registration_generation": receipt["generation"],
                "operation_id": str(uuid4()), "capture_id": "storage-http-capture-" + config["run_identity"],
                "content_generation": "1", "sha256": hashlib.sha256(data).hexdigest(), "byte_count": str(total)}
            initial = request("upload_create", "POST", "/frame-relay/v1/uploads", payload=binding, secret=secret)
            expected_binding = initial["binding"]
            if any(expected_binding.get(k) != v for k, v in binding.items()) or expected_binding["chunk_size"] != "8388608":
                raise RuntimeError("Created upload binding mismatch")
            session = expected_binding["session_id"]
            path = "/frame-relay/v1/uploads/" + session
            if request("upload_replay", "POST", "/frame-relay/v1/uploads", payload=binding, secret=secret) != initial:
                raise RuntimeError("Upload replay changed session")
            passed("upload_exact_replay")
            request("operation_conflict", "POST", "/frame-relay/v1/uploads",
                    payload={**binding, "sha256": "f" * 64}, secret=secret, expected=(409,))
            passed("operation_content_conflict_rejected")
            request("wrong_secret", "GET", path, binding=binding, secret="0" * 64, expected=(403,))
            request("wrong_bearer", "GET", path, binding=binding, secret=secret, bearer="invalid", expected=(401,))
            request("missing_secret", "GET", path, binding=binding, expected=(401,))
            passed("authorization_mismatches_rejected")
            replacements = {"destination_id": str(uuid4()), "registration_id": str(uuid4()),
                "registration_generation": str(int(binding["registration_generation"]) + 1),
                "operation_id": str(uuid4()), "capture_id": "other-capture", "content_generation": "2",
                "sha256": "e" * 64, "byte_count": str(total + 1)}
            for key, value in replacements.items():
                request("binding_mismatch_" + key, "GET", path, binding={**binding, key: value},
                        secret=secret, expected=(403, 409))
                passed("binding_mismatch_" + key + "_rejected")
            chunk_size = int(expected_binding["chunk_size"])
            for index, start in enumerate(range(0, total, chunk_size)):
                block = data[start:start + chunk_size]
                headers = {"Content-Range": "bytes " + str(start) + "-" + str(start + len(block) - 1) + "/" + str(total),
                           "X-Chunk-SHA256": hashlib.sha256(block).hexdigest(),
                           "Content-Type": "application/octet-stream"}
                if index == 0:
                    request("chunk_bad_content", "PUT", path + "/chunks/0", binding=binding, secret=secret,
                            body=block, extra={**headers, "X-Chunk-SHA256": "0" * 64}, expected=(409,))
                    passed("chunk_content_mismatch_rejected")
                chunk = request("chunk", "PUT", path + "/chunks/" + str(index), binding=binding,
                                secret=secret, body=block, extra=headers)
                if chunk != {"chunk_index": index, "byte_count": str(len(block)), "sha256": headers["X-Chunk-SHA256"]}:
                    raise RuntimeError("Chunk acknowledgement mismatch")
                if index == 0:
                    if request("chunk_replay", "PUT", path + "/chunks/0", binding=binding,
                               secret=secret, body=block, extra=headers) != chunk:
                        raise RuntimeError("Chunk replay changed acknowledgement")
                    passed("chunk_exact_replay")
                    request("partial_finalize", "POST", path + "/finalize", binding=binding,
                            secret=secret, expected=(409,))
                    partial = request("partial_get", "GET", path, binding=binding, secret=secret)
                    if partial["status"] != "receiving" or partial["evidence"] is not None or partial["chunk_indexes"] != [0]:
                        raise RuntimeError("Partial upload generated storage evidence")
                    passed("partial_upload_no_evidence")
            before = request("received_get", "GET", path, binding=binding, secret=secret)
            if before["status"] != "receiving" or before["evidence"] is not None or before["chunk_indexes"] != [0, 1, 2]:
                raise RuntimeError("Transport completion generated storage evidence")
            passed("three_chunks_transport_only")
            request("finalize", "POST", path + "/finalize", binding=binding, secret=secret)
            while True:
                result = request("final_get", "GET", path, binding=binding, secret=secret)
                if result["status"] == "completed":
                    break
                if result["status"] != "finalizing":
                    raise RuntimeError("Finalize did not complete")
                time.sleep(0.1)
            check_proof(result, binding, expected_binding)
            passed("final_readback_evidence")
            if request("finalize_replay", "POST", path + "/finalize", binding=binding, secret=secret) != result:
                raise RuntimeError("Finalized replay changed proof")
            passed("finalize_exact_replay")
            request("completed_cancel", "DELETE", path, binding=binding, secret=secret, expected=(409,))
            passed("completed_original_cancel_rejected")
            life.write_json(state_path, {"run_identity": config["run_identity"], "registration_secret": secret,
                "registration_request": registration_request, "registration_receipt": receipt,
                "binding": binding, "completed": result}, private=True)
        else:
            if stat.S_IMODE(state_path.lstat().st_mode) != 0o600:
                raise RuntimeError("Restart client state mode mismatch")
            state = life.read_json(state_path)
            if state.get("run_identity") != config["run_identity"]:
                raise RuntimeError("Restart client identity mismatch")
            secret = state["registration_secret"]
            binding = state["binding"]
            expected_binding = state["completed"]["binding"]
            path = "/frame-relay/v1/uploads/" + expected_binding["session_id"]
            receipt = request("registration_lookup", "GET",
                "/frame-relay/v1/registration-intents/" + state["registration_request"]["operation_id"],
                binding={"destination_id": binding["destination_id"]}, secret=secret)
            if receipt != state["registration_receipt"]:
                raise RuntimeError("Process restart changed registration")
            passed("restart_same_registration")
            result = request("restart_get", "GET", path, binding=binding, secret=secret)
            check_proof(result, binding, expected_binding)
            if result != state["completed"] or result != life.read_json(runtime / "phase-1/http-results.json")["completed"]:
                raise RuntimeError("Process restart changed session/evidence")
            passed("restart_same_session_and_evidence")
            if request("restart_create_replay", "POST", "/frame-relay/v1/uploads",
                       payload=binding, secret=secret) != {"binding": expected_binding}:
                raise RuntimeError("Restart replay allocated a new session")
            passed("restart_upload_exact_replay")
            if request("restart_finalize_replay", "POST", path + "/finalize", binding=binding, secret=secret) != result:
                raise RuntimeError("Restart finalize changed evidence")
            passed("restart_finalize_exact_replay")
        report["completed"] = result
        report["registration_receipt"] = receipt
        report["passed"] = tuple(report["cases"]) == life.HTTP_CASES[phase]
    except BaseException as error:
        report["failure_type"] = type(error).__name__
    finally:
        for connection in all_connections:
            connection.close()
        report["all_connections_closed"] = all(connection.sock is None for connection in all_connections)
        report["elapsed_seconds"] = time.monotonic() - started
        report["passed"] = report["passed"] and report["all_connections_closed"]
        # State survives just the two child processes; supervisor finally deletes it.
        # No credential or credential hash is persisted in public evidence/logs.
        credentials.clear()
        token = secret = None
        life.write_json(directory / "http-results.json", report)
    print(json.dumps({"storage_phase": phase, "passed": report["passed"], "cases": len(report["cases"])}))
    return 0 if report["passed"] else 70


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"passed": False, "failure_type": type(error).__name__}))
        raise SystemExit(70) from None
