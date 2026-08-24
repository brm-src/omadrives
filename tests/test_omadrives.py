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


if __name__ == "__main__":
    unittest.main()
