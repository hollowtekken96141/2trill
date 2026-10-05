#!/usr/bin/env python3
"""Prints the UDID of an available iPhone simulator, newest iOS runtime first."""
import json
import subprocess
import sys

out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
devices = json.loads(out)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if "iPhone" in device["name"]:
            print(device["udid"])
            print(f"{device['name']} ({runtime.rsplit('.', 1)[-1]})", file=sys.stderr)
            sys.exit(0)
sys.exit("no iPhone simulator found")
