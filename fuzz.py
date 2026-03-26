import subprocess
import random
import time
import math
from pathlib import Path

# ---- CONFIG ----
BPE_CMD = ["zig", "build", "run", "--release=fast", "-Ddebug", "--", "test.txt"]
FILE_NAME = "test.txt"

VOWELS = "aeiou"
CONS = "bcdfghjklmnpqrstvwxyz"
SPACE = " "

# seed from current time
seed = time.time_ns()
random.seed(seed)
print(f"Seed: {seed}")

# ---- Custom time function ----
BASE_TIME_SPENT = 10
BASE_TIME = 0.005 
LOG_SCALE = 10 

def time_for_size(n):
    """Scale time with input size and log; no cap."""
    return BASE_TIME_SPENT + BASE_TIME * n + LOG_SCALE * math.log(n + 1)

# ---- Text generation ----
def gen_text(n):
    """Generate biased random text of n bytes."""
    out = []
    for _ in range(n):
        r = random.random()
        if r < 0.65:
            out.append(random.choice(VOWELS))
        elif r < 0.90:
            out.append(random.choice(CONS))
        else:
            out.append(SPACE)
    return "".join(out)

# ---- Fibonacci generator ----
def fib_sequence():
    a, b = 3, 5
    while True:
        yield a
        a, b = b, a + b

# ---- Main fuzzing loop ----
def main():
    for n in fib_sequence():
        duration = time_for_size(n)
        print(f"Testing size: {n} for {duration:.2f}s")

        end_time = time.time() + duration

        count = 0;
        while time.time() < end_time:
            count += 1;
            text = gen_text(n)
            Path(FILE_NAME).write_text(text)

            proc = subprocess.run(BPE_CMD,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)

            if proc.returncode != 0:
                print("BPE FAILED!")
                print(f"Failing size: {n}")
                print(f"Input saved in: {FILE_NAME}")
                return
        print(f"Did {count} iteration");

if __name__ == "__main__":
    main()
