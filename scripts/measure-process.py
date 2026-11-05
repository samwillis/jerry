#!/usr/bin/env python3
"""Read-only local CPU/RSS sample for a running prototype; no telemetry is sent."""
import argparse
import json
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=30)
args = parser.parse_args()

def sample():
    fields = subprocess.check_output(["ps", "-p", str(args.pid), "-o", "time=,rss="], text=True).split()
    parts = fields[0].split(":")
    cpu = sum(float(value) * 60 ** index for index, value in enumerate(reversed(parts)))
    return cpu, int(fields[1]) / 1024

started = time.monotonic()
initial, memory = sample()
memories = [memory]
for _ in range(args.seconds):
    time.sleep(1)
    final, memory = sample()
    memories.append(memory)
elapsed = time.monotonic() - started
print(json.dumps({"seconds": round(elapsed, 1), "average_cpu_percent_of_one_core": round((final-initial)/elapsed*100, 2), "rss_mib_min": round(min(memories), 1), "rss_mib_max": round(max(memories), 1), "rss_mib_end": round(memory, 1)}, indent=2))
