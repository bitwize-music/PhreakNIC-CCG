#!/usr/bin/env python3
"""Launch the compiled app in an available iPhone Simulator and capture evidence."""
import json
import pathlib
import subprocess
import time


def run(*args):
    print("Running:", " ".join(args), flush=True)
    return subprocess.check_output(args, text=True, timeout=300)


output = pathlib.Path("build/ios")
app = (output / "simulator/Build/Products/Release-iphonesimulator/PhreakNICCCG.app").resolve()
if not (app / "PhreakNICCCG").is_file():
    raise RuntimeError("Simulator executable missing; build the Simulator app successfully first")
devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))
device = next(
    d for runtime, entries in sorted(devices["devices"].items(), reverse=True) if "iOS" in runtime
    for d in entries if d["name"].startswith("iPhone") and d["isAvailable"]
)
udid = device["udid"]
print("Testing on", device["name"], udid, flush=True)
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b")
print(run("file", str(app / "PhreakNICCCG")), flush=True)
print(run("xcrun", "vtool", "-show-build", str(app / "PhreakNICCCG")), flush=True)
run("xcrun", "simctl", "install", udid, str(app))
with (output / "simulator.log").open("w") as log:
    process = subprocess.Popen(
        ["xcrun", "simctl", "launch", "--terminate-running-process", "--console",
         udid, "com.nirtom84.phreakniccg"], stdout=log, stderr=subprocess.STDOUT
    )
    try:
        time.sleep(15)
        if process.poll() is not None:
            raise RuntimeError("Simulator app exited early; inspect simulator.log")
        run("xcrun", "simctl", "io", udid, "screenshot", str(output / "simulator.png"))
    finally:
        process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
log_text = (output / "simulator.log").read_text()
for error in ("SCRIPT ERROR:", "Parse Error:", "Failed loading resource"):
    if error in log_text:
        raise RuntimeError(f"{error} in simulator.log")
print("Simulator app stayed running; screenshot captured.")
