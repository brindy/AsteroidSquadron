#!/usr/bin/env python3
"""Generate and verify Sparkle metadata without exporting the signing key."""

import argparse
import base64
import copy
import hashlib
import html
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ACCOUNT = "asteroid-squadron"
FEED_PATH = ROOT / "app-updates/asteroid-squadron/appcast.xml"
FEED_URL = "https://raw.githubusercontent.com/brindy/AsteroidSquadron/main/app-updates/asteroid-squadron/appcast.xml"
REPOSITORY = "https://github.com/brindy/AsteroidSquadron"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("atom", "http://www.w3.org/2005/Atom")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*arguments, capture=False):
    return subprocess.run(arguments, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def sha256(path):
    with path.open("rb") as source:
        digest = hashlib.sha256()
        for block in iter(lambda: source.read(1_048_576), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_feed(data):
    require(b"<!DOCTYPE" not in data.upper(), "The previous feed contains an unsupported XML document type.")
    root = ET.fromstring(data)
    require(root.tag == "rss" and root.find("channel") is not None,
            "The update feed is not an RSS channel.")
    return root


def previous_feed(path, url):
    if path is not None:
        return path.read_bytes()
    if FEED_PATH.exists():
        return FEED_PATH.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": "AsteroidSquadronRelease/1"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(16_777_217)
            content_type = response.headers.get_content_type()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print("No previous Sparkle feed is published yet.")
            return None
        raise
    require(len(data) <= 16_777_216, "The published update feed is unexpectedly large.")
    # A site's catch-all page can return HTTP 200 before the feed exists.
    prefix = data.lstrip().lower()
    if content_type == "text/html" and (prefix.startswith(b"<!doctype html") or prefix.startswith(b"<html")):
        print("The feed URL currently serves an HTML page; preparing the first Sparkle feed.")
        return None
    parse_feed(data)
    return data


def inline_markup(text):
    escaped = html.escape(text)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)


def release_notes(markdown, version):
    parts = [f"<h2>Asteroid Squadron {html.escape(version)}</h2>"]
    in_list = False
    paragraph = []

    def flush_paragraph():
        if paragraph:
            parts.append("<p>" + inline_markup(" ".join(paragraph)) + "</p>")
            paragraph.clear()

    for line in markdown.splitlines():
        line = line.strip()
        if line.startswith("- "):
            flush_paragraph()
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append("<li>" + inline_markup(line[2:]) + "</li>")
        else:
            if in_list:
                parts.append("</ul>")
                in_list = False
            if not line:
                flush_paragraph()
            else:
                paragraph.append(line.lstrip("# "))
    if in_list:
        parts.append("</ul>")
    flush_paragraph()
    return "\n".join(parts) + "\n"


def item_version(item):
    enclosure = item.find("enclosure")
    value = item.findtext(f"{{{SPARKLE}}}version")
    if value is None and enclosure is not None:
        value = enclosure.get(f"{{{SPARKLE}}}version")
    require(value is not None and value.isdigit(), "An update item has no numeric build version.")
    return int(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?", default="v" + (ROOT / "VERSION").read_text().strip())
    parser.add_argument("--previous-feed", type=pathlib.Path,
                        help="Use this existing signed appcast instead of the repository or published feed.")
    args = parser.parse_args()
    require(re.fullmatch(r"v[0-9]+\.[0-9]+(?:\.[0-9]+)?", args.tag), "Expected a release tag such as v1.34.")
    version = args.tag[1:]
    folder = ROOT / "build/releases" / args.tag
    app = folder / "Asteroid Squadron.app"
    evidence = json.loads((folder / "RELEASE-EVIDENCE.json").read_text())
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(evidence["version"] == version == info["CFBundleShortVersionString"], "The release version does not match its evidence.")
    require(str(evidence["build"]) == info["CFBundleVersion"] and info["CFBundleVersion"].isdigit(),
            "The release build number does not match its evidence.")
    build = int(info["CFBundleVersion"])
    require(info["CFBundleIdentifier"] == "dev.brindy.asteroid-squadron", "Unexpected application bundle ID.")
    require(evidence["architectures"] == ["arm64"], "The update must contain the Apple Silicon release.")
    require(info.get("SUFeedURL") == FEED_URL, "The built app does not use the expected update feed.")
    require(info.get("SUVerifyUpdateBeforeExtraction") and info.get("SURequireSignedFeed"),
            "The app must require signed archives and a signed update feed.")
    public_key = (ROOT / "Resources/SparklePublicKey.txt").read_text().strip()
    require(len(base64.b64decode(public_key, validate=True)) == 32 and info.get("SUPublicEDKey") == public_key,
            "The app's update public key does not match the repository.")
    for kind in ["app", "dmg"]:
        require(evidence[kind + "Notarization"]["status"] == "Accepted", "Notarization is incomplete.")
    archive = folder / f"Asteroid-Squadron-{version}-arm64.dmg"
    archive_hash = sha256(archive)
    require(evidence["sha256"].get(archive.name) == archive_hash, "The signed DMG changed after release verification.")
    tools = pathlib.Path(run(str(ROOT / "scripts/fetch-sparkle.sh"), capture=True).strip()) / "bin"
    for name in ["generate_appcast", "sign_update", "generate_keys"]:
        require((tools / name).is_file(), f"Sparkle's {name} tool is missing.")
    keychain_key = run(str(tools / "generate_keys"), "--account", ACCOUNT, "-p", capture=True).strip()
    require(keychain_key == public_key, "The Keychain signing key does not match the app's update public key.")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    run("xcrun", "stapler", "validate", str(app))
    run("xcrun", "stapler", "validate", str(archive))
    old_data = previous_feed(args.previous_feed, FEED_URL)
    destination = folder / "sparkle"
    destination.mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="sparkle-update.", dir=ROOT / ".cache") as temporary:
        staging = pathlib.Path(temporary)
        feed = staging / "appcast.xml"
        old_items = []
        if old_data is not None:
            feed.write_bytes(old_data)
            run(str(tools / "sign_update"), "--account", ACCOUNT, "--verify", str(feed))
            old_items = list(parse_feed(old_data).find("channel").findall("item"))
            require(all(item_version(item) <= build for item in old_items),
                    "A newer build is already in the update feed.")
        shutil.copyfile(archive, staging / archive.name)
        notes = release_notes((ROOT / "releases" / f"{args.tag}.md").read_text(), version)
        (staging / f"{archive.stem}.html").write_text(notes)
        release_url = f"{REPOSITORY}/releases/tag/{args.tag}"
        download_prefix = f"{REPOSITORY}/releases/download/{args.tag}/"
        run(str(tools / "generate_appcast"), "--account", ACCOUNT,
            "--download-url-prefix", download_prefix, "--link", release_url,
            "--versions", str(build), "--maximum-versions", "0", "--maximum-deltas", "0",
            "--embed-release-notes", "-o", str(feed), str(staging))
        generated = parse_feed(feed.read_bytes())
        channel = generated.find("channel")
        preserved = [item for item in old_items if item_version(item) != build]
        # Preserve previous download URLs and notes exactly even if the generator
        # refreshes their metadata using the new release's URL prefix.
        for item in preserved:
            for existing in list(channel.findall("item")):
                if item_version(existing) == item_version(item):
                    channel.remove(existing)
            channel.append(copy.deepcopy(item))
        if preserved:
            ET.indent(generated, space="  ")
            feed.write_bytes(ET.tostring(generated, encoding="utf-8", xml_declaration=True))
        items = [item for item in channel.findall("item") if item_version(item) == build]
        require(len(items) == 1, "The generated feed must contain exactly one item for this build.")
        item = items[0]
        require(item.findtext(f"{{{SPARKLE}}}shortVersionString") == version, "The feed's display version is incorrect.")
        enclosure = item.find("enclosure")
        require(enclosure is not None, "The update item has no download enclosure.")
        require(enclosure.get("url") == download_prefix + archive.name, "The enclosure points to an unexpected download.")
        require(int(enclosure.get("length", "0")) == archive.stat().st_size, "The update download length is incorrect.")
        signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
        require(len(base64.b64decode(signature, validate=True)) == 64, "The update has no valid EdDSA signature.")
        require(item.find("description") is not None, "The update has no embedded release notes.")
        run(str(tools / "sign_update"), "--account", ACCOUNT, "--verify", str(archive), signature)
        run(str(tools / "sign_update"), "--account", ACCOUNT, str(feed))
        run(str(tools / "sign_update"), "--account", ACCOUNT, "--verify", str(feed))
        output = destination / "appcast.xml"
        shutil.copyfile(feed, output)
        (destination / "release-notes.html").write_text(notes)
        manifest = {
            "version": version, "build": str(build), "sourceCommit": evidence["sourceCommit"],
            "feedURL": FEED_URL, "archive": archive.name, "archiveURL": enclosure.get("url"),
            "archiveSHA256": archive_hash, "archiveLength": archive.stat().st_size,
            "feedSHA256": sha256(output), "preservedBuilds": [item_version(item) for item in old_items if item_version(item) != build],
            "signingAccount": ACCOUNT, "signedFeedVerified": True, "archiveSignatureVerified": True,
        }
        (destination / "SPARKLE-EVIDENCE.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared signed Sparkle update: {destination}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"Could not prepare Sparkle update: {error}", file=sys.stderr)
        sys.exit(1)
