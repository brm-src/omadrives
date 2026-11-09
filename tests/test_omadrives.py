import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import omadrives


class OmaDrivesHelperTests(unittest.TestCase):
    def test_human_size_uses_compact_units(self):
        self.assertEqual(omadrives.human_size(1024), "1K")
        self.assertEqual(omadrives.human_size(1024**2), "1M")

    def test_run_caps_output_bytes(self):
        result = omadrives.run([sys.executable, "-c", "print('x' * 1_000_000)"])
        self.assertLessEqual(len(result.stdout.encode()), omadrives.MAX_CAPTURE_BYTES)

    def test_run_kills_on_timeout(self):
        result = omadrives.run(["sleep", "5"], timeout=1)
        self.assertNotEqual(result.returncode, 0)

    def test_run_captures_stderr_and_returncode(self):
        result = omadrives.run(["ls", "/definitely/not/here"])
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stderr.strip())

    def test_partition_walk_skips_swap_and_keeps_mounted_unknown_fs(self):
        node = {
            "name": "disk",
            "children": [
                {"name": "swap", "fstype": "swap"},
                {"name": "mounted", "mountpoints": ["/media/usb"]},
            ],
        }
        found = list(omadrives.iter_partitions(node))
        self.assertEqual([item["name"] for item in found], ["mounted"])

    def test_removable_detection_includes_unformatted_media(self):
        self.assertTrue(omadrives.has_removable_devices({
            "blockdevices": [{"name": "sdb", "rm": True, "type": "disk"}],
        }))
        self.assertFalse(omadrives.has_removable_devices({
            "blockdevices": [{"name": "zram0", "rm": True, "type": "disk"}],
        }))


    def test_btrfs_root_reports_slash_and_is_system(self):
        data = {"blockdevices": [{
            "name": "nvme0n1", "path": "/dev/nvme0n1", "type": "disk",
            "children": [{
                "name": "root", "path": "/dev/mapper/root", "type": "crypt", "fstype": "btrfs",
                "mountpoints": ["/var/cache/pacman/pkg", "/home", "/"],
            }],
        }]}
        drive = omadrives.collect_drives(data)[0]
        self.assertEqual(drive["mountpoint"], "/")
        self.assertTrue(drive["system"])

if __name__ == "__main__":
    unittest.main()
