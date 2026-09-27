"""Check the pinned Android bootstrap files before executing Gradle."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def check(root):
    root = Path(root)
    approved = json.loads((root / "release/android-toolchain.json").read_text(encoding="utf-8"))
    android = root / "apps/android/android"
    jar = android / "gradle/wrapper/gradle-wrapper.jar"
    if hashlib.sha256(jar.read_bytes()).hexdigest() != approved["wrapper_sha256"]:
        raise ValueError("Gradle wrapper JAR does not match the reviewed checksum")
    properties = dict(line.split("=", 1) for line in (jar.parent / "gradle-wrapper.properties").read_text(encoding="utf-8").splitlines() if "=" in line)
    expected_url = f"https\\://services.gradle.org/distributions/gradle-{approved['gradle_version']}-all.zip"
    if properties.get("distributionUrl") != expected_url or properties.get("distributionSha256Sum") != approved["distribution_sha256"]:
        raise ValueError("Gradle distribution differs from the reviewed pin")
    ns = {"v": "https://schema.gradle.org/dependency-verification"}
    metadata = ET.parse(android / "gradle/verification-metadata.xml").getroot()
    if metadata.findtext("v:configuration/v:verify-metadata", namespaces=ns) != "true":
        raise ValueError("Dependency metadata verification must remain enabled")
    if metadata.findall("v:configuration/v:trusted-artifacts", ns):
        raise ValueError("Review verification exemptions before packaging")
    components = metadata.findall("v:components/v:component", ns)
    for record in approved["platform_artifacts"]:
        component = next((c for c in components if all(c.get(k) == record[k] for k in ("group", "name", "version"))), None)
        if component is None:
            raise ValueError("Reviewed platform dependency is absent")
        artifact = next((a for a in component.findall("v:artifact", ns) if a.get("name") == record["artifact"]), None)
        if artifact is None or record["sha256"] not in [s.get("value") for s in artifact.findall("v:sha256", ns)]:
            raise ValueError("Platform dependency checksum differs from the reviewed pin")
    return len(components)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        count = check(args.root)
        print(f"Android bootstrap pins verified; {count} dependency components recorded")
        return 0
    except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as error:
        print(f"Android bootstrap check failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
