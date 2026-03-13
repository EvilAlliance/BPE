import subprocess
from pathlib import Path

# ---- CONFIG ----
BPE_CMD_BASE = ["zig", "build", "run", "-Ddebug", "--"]
INPUT_DIR = Path("verify")   # folder containing the files


def run_file(file_path: Path):
    """Run program with a specific file and return success."""
    cmd = BPE_CMD_BASE + [str(file_path)]
    proc = subprocess.run(cmd)
    return proc.returncode == 0


def main():
    if not INPUT_DIR.exists():
        print(f"Directory not found: {INPUT_DIR}")
        return

    files = sorted(INPUT_DIR.iterdir())

    if not files:
        print("No files found in verify/")
        return

    for f in files:
        if not f.is_file():
            continue

        print(f"Testing: {f}")

        success = run_file(f)

        if not success:
            print("PROGRAM FAILED!")
            print(f"Failing file: {f}")
            return

    print("All files in verify/ executed successfully.")


if __name__ == "__main__":
    main()
