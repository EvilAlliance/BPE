import subprocess
from pathlib import Path

# ---- CONFIG ----
BPE_CMD_BASE = ["zig", "build", "run", "-Ddebug", "--"]
INPUT_DIR = Path("verify")   # folder containing the files


def run_file(file_path: Path):
    """Run program with a specific file and return success."""
    cmd = BPE_CMD_BASE + [str(file_path)]
    proc = subprocess.run(cmd,  
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL)
    return proc.returncode == 0


def main():
    if not INPUT_DIR.exists():
        print(f"Directory not found: {INPUT_DIR}")
        return

    files = sorted(INPUT_DIR.iterdir())

    if not files:
        print("No files found in verify/")
        return

    results = []

    for f in files:
        if not f.is_file():
            continue

        print(f"Running: {f}")

        success = run_file(f)

        if success:
            print(f"✅ SUCCESS: {f}")
        else:
            print(f"❌ FAILED : {f}")

        results.append((f, success))

    print("\n----- TEST SUMMARY -----")

    passed = 0
    failed = 0

    for f, success in results:
        status = "PASS" if success else "FAIL"
        print(f"{status:4} - {f}")

        if success:
            passed += 1
        else:
            failed += 1

    print("\n------------------------")
    print(f"Total tests : {passed + failed}")
    print(f"Passed      : {passed}")
    print(f"Failed      : {failed}")


if __name__ == "__main__":
    main()
