#!/usr/bin/env python3
"""Unsigned iPhone IPA integrity check. Does not validate LiveContainer runtime."""
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(ipa, project, version):
    with zipfile.ZipFile(ipa) as archive:
        require(archive.testzip() is None, 'Corrupt ZIP entry')
        prefix = f'Payload/{project["name"]}.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        executable = info['CFBundleExecutable']
        require(executable and '/' not in executable and '\\' not in executable, 'Invalid executable name')
        binary = archive.read(prefix + executable)
        require(len(binary) >= 32 and binary[:4] == b'\xcf\xfa\xed\xfe', 'Not thin 64-bit Mach-O')
        require(struct.unpack_from('<I', binary, 4)[0] == 0x0100000C, 'Not an ARM64 executable')
        require(struct.unpack_from('<I', binary, 12)[0] == 2, 'Not a Mach-O executable')
        commands, size = struct.unpack_from('<II', binary, 16)
        end = 32 + size
        require(end <= len(binary), 'Truncated load commands')
        offset = 32
        device_platform = False
        for _ in range(commands):
            require(offset + 8 <= end, 'Truncated load command')
            command, length = struct.unpack_from('<II', binary, offset)
            require(length >= 8 and offset + length <= end, 'Invalid load command size')
            if command == 0x32:  # LC_BUILD_VERSION
                require(length >= 24, 'Invalid build version command')
                require(struct.unpack_from('<I', binary, offset + 8)[0] == 2, 'Not an iOS device binary')
                device_platform = True
            offset += length
        require(offset == end and device_platform, 'Missing iOS device build version')
        require(info.get('CFBundlePackageType') == 'APPL', 'Not an application bundle')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Not an iPhoneOS bundle')
        require(info.get('CFBundleIdentifier') == project['bundleIdentifier'], 'Incorrect bundle identifier')
        require(info.get('CFBundleShortVersionString') == version['version'], 'Incorrect bundle version')
        require(info.get('CFBundleVersion') == str(version['build']), 'Incorrect build number')
        require(int(info.get('MinimumOSVersion', '0').split('.')[0]) >= 17, 'Incorrect minimum iOS version')
        return info


if __name__ == '__main__':
    project = json.loads((BASE / 'Config/project.json').read_text())
    version = json.loads((BASE / 'Config/version.json').read_text())
    ipa = Path(sys.argv[1])
    info = verify(ipa, project, version)
    print(f'PASS: {ipa.name}: iOS ARM64 {info["CFBundleIdentifier"]} v{version["version"]} ({version["build"]}); runtime not tested')
