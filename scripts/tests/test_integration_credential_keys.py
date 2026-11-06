#!/usr/bin/env python3
"""Prove the actual codec crosses distinct device vaults in isolated test VMs."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="pleya-credential-isolation-", dir="/tmp") as tmp:
        for role in ["source", "receiver"]:
            subprocess.run([
                "flutter", "test", "test/services/integration_credential_key_isolation_test.dart",
                "--dart-define=CREDENTIAL_TEST_ROLE=" + role,
                "--dart-define=CREDENTIAL_TEST_DIR=" + tmp,
            ], cwd=root, check=True)
    print("Actual codec passed between independent VMs with different device vault keys")


if __name__ == "__main__":
    main()
