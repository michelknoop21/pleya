import tempfile
import unittest
from pathlib import Path

import download_counter


class DownloadCounterTest(unittest.TestCase):
    def test_download_starts_are_persisted_without_visitor_data(self):
        original = download_counter.DB_PATH
        with tempfile.TemporaryDirectory() as directory:
            download_counter.DB_PATH = Path(directory) / "downloads.sqlite3"
            try:
                self.assertEqual(download_counter.counts()["total"], 0)
                download_counter.record_start()
                download_counter.record_start()
                self.assertEqual(download_counter.counts()["total"], 2)
            finally:
                download_counter.DB_PATH = original


if __name__ == "__main__":
    unittest.main()
