#!/usr/bin/env python3
"""The AltStore / SideStore source for the iPhone app (apps.json on the
download site). Adding it once in SideStore or AltStore lists Apex Circuit
there, installs it in a tap, and shows each new version as an update.

    python3 .github/make_source.py --version 0.1.83 --build 83 --size 24695646 \
        --plist Payload/ApexCircuit.app/Info.plist --notes "What's new" > apps.json

The app's permissions are read from its own Info.plist: AltStore refuses an
app whose source lists different ones.
"""
import argparse
import json
import plistlib
import sys
from datetime import datetime, timezone

SITE = "https://sohamtiwari-prog.github.io/apex-circuit"
REPO = "https://github.com/sohamtiwari-prog/apex-circuit"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--size", type=int, required=True)
    ap.add_argument("--plist", required=True)
    ap.add_argument("--notes", default="")
    a = ap.parse_args()
    with open(a.plist, "rb") as f:
        info = plistlib.load(f)
    privacy = {k: str(v) for k, v in info.items() if k.endswith("UsageDescription")}
    bundle = info.get("CFBundleIdentifier", "com.sohamtiwari.apexcircuit")
    min_os = str(info.get("MinimumOSVersion", "14.0"))
    url = f"{REPO}/releases/download/v{a.version}/ApexCircuit-iPhone.ipa"
    date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    desc = ("A racing game for your phone: karts, F4, F3, F2 and Grand Prix cars on "
            "original and real-world circuits. Career from karts to Grand Prix, "
            "championships, time trials against friends' ghost laps, and races with "
            "friends online. Same game as the Android app; progress moves between "
            "them with a backup code.")
    notes = a.notes.strip() or f"Version {a.version}."
    app = {
        "name": "Apex Circuit",
        "bundleIdentifier": bundle,
        "developerName": "sohamtiwari-prog",
        "subtitle": "Karts to Grand Prix, on your phone.",
        "localizedDescription": desc,
        "iconURL": f"{SITE}/icon.png",
        "tintColor": "#FFD200",
        "category": "games",
        "screenshots": [],
        "versions": [{
            "version": a.version,
            "buildVersion": a.build,
            "date": date,
            "localizedDescription": notes,
            "downloadURL": url,
            "size": a.size,
            "minOSVersion": min_os,
        }],
        "appPermissions": {"entitlements": [], "privacy": privacy},
        # (Older SideStore and AltStore read these instead of versions.)
        "version": a.version,
        "versionDate": date,
        "versionDescription": notes,
        "downloadURL": url,
        "size": a.size,
    }
    source = {
        "name": "Apex Circuit",
        "identifier": "io.github.sohamtiwari-prog.apexcircuit",
        "subtitle": "The Apex Circuit iPhone app",
        "description": "Install Apex Circuit and get its updates. Free; signed on your phone with your own Apple ID.",
        "iconURL": f"{SITE}/icon.png",
        "website": SITE + "/",
        "tintColor": "#FFD200",
        "nsfw": False,
        "featuredApps": [bundle],
        "apps": [app],
        "news": [],
    }
    json.dump(source, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
