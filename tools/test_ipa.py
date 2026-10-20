#!/usr/bin/env python3
"""Check package validation against deliberately valid and malformed fixtures."""
import io
import plistlib
import struct
import unittest
import zipfile

from verify_ipa import verify


class IPATests(unittest.TestCase):
    def package(self, *, platform=2, cpu=0x0100000C, build='3', truncated=False):
        binary = struct.pack('<8I', 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0)
        binary += struct.pack('<6I', 0x32, 24, platform, 0x110000, 0x1B0000, 0)
        if truncated:
            binary = binary[:-1]
        info = dict(CFBundleExecutable='FlowPaste', CFBundlePackageType='APPL',
                    CFBundleSupportedPlatforms=['iPhoneOS'], CFBundleIdentifier='dev.test',
                    CFBundleShortVersionString='0.2.0', CFBundleVersion=build, MinimumOSVersion='17.0')
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('Payload/FlowPaste.app/Info.plist', plistlib.dumps(info))
            archive.writestr('Payload/FlowPaste.app/FlowPaste', binary)
        output.seek(0)
        return output

    def check(self, **options):
        return verify(self.package(**options), {'name': 'FlowPaste', 'bundleIdentifier': 'dev.test'}, {'version': '0.2.0', 'build': 3})

    def test_device_package(self):
        self.assertEqual(self.check()['CFBundleVersion'], '3')

    def test_reject_simulator(self):
        with self.assertRaisesRegex(ValueError, 'device binary'):
            self.check(platform=7)

    def test_reject_wrong_architecture(self):
        with self.assertRaisesRegex(ValueError, 'ARM64'):
            self.check(cpu=0x01000007)

    def test_reject_wrong_build(self):
        with self.assertRaisesRegex(ValueError, 'build number'):
            self.check(build='2')

    def test_reject_truncated_binary(self):
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            self.check(truncated=True)


if __name__ == '__main__':
    unittest.main()
