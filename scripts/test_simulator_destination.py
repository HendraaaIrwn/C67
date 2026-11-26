import unittest

from simulator_destination import ios_destination


class SimulatorDestinationTests(unittest.TestCase):
    devices = {
        "com.apple.CoreSimulator.SimRuntime.tvOS-18-0": [
            {"name": "Apple TV", "isAvailable": True, "udid": "tv"},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
            {"name": "iPhone 18 Pro", "isAvailable": True, "udid": "new"},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
            {"name": "iPhone 16", "isAvailable": False, "udid": "unavailable"},
            {"name": "iPad", "isAvailable": True, "udid": "ipad"},
            {"name": "iPhone 16 Pro", "isAvailable": True, "udid": "legacy"},
        ],
    }

    def test_default_keeps_first_available_iphone(self):
        self.assertEqual(ios_destination(self.devices), "platform=iOS Simulator,id=new")

    def test_requested_major_or_minor_uses_a_matching_iphone(self):
        for version in ("18", "18.6"):
            with self.subTest(version=version):
                self.assertEqual(ios_destination(self.devices, version), "platform=iOS Simulator,id=legacy")

    def test_missing_requested_runtime_does_not_fall_back(self):
        self.assertIsNone(ios_destination(self.devices, "18.5"))
