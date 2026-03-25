from pathlib import Path
import subprocess
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

# ---- CONFIG ----
BPE_CMD_BASE = ["zig", "build", "--release=fast", "run", "-Ddebug", "--"]
INPUT_DIR = Path("verify")

# Ask OS for number of CPUs (fallback to 4 if None)
MAX_WORKERS = os.cpu_count() or 4


def run_file(file_path: Path):
    """Run program with a specific file and return (file, success)."""
    cmd = BPE_CMD_BASE + [str(file_path)]
    proc = subprocess.run(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    return file_path, proc.returncode == 0


def main():
    if not INPUT_DIR.exists():
        print(f"Directory not found: {INPUT_DIR}")
        return

    files = [f for f in INPUT_DIR.iterdir() if f.is_file()]
    files.sort(key=lambda f: (f.stat().st_size, f.name), reverse=True)

    if not files:
        print("No files found in verify/")
        return

    results = []

    print(f"Running {len(files)} files with {MAX_WORKERS} threads...\n")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(run_file, f) for f in files]

        for future in as_completed(futures):
            f, success = future.result()

            if success:
                print(f"✅ SUCCESS: {f}")
            else:
                print(f"❌ FAILED : {f}")

            results.append((f, success))

    # ---- SUMMARY ----
    print("\n----- TEST SUMMARY -----")

    passed = sum(1 for _, s in results if s)
    failed = len(results) - passed

    for f, success in sorted(results):
        print(f"{'PASS' if success else 'FAIL':4} - {f}")

    print("\n------------------------")
    print(f"Total tests : {len(results)}")
    print(f"Passed      : {passed}")
    print(f"Failed      : {failed}")


if __name__ == "__main__":
    main()
