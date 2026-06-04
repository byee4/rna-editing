import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"))

import build_redits_counts as b  # noqa: E402

HEADER = ("Region\tPosition\tReference\tStrand\tCoverage-q30\tMeanQ\t"
          "BaseCount[A,C,G,T]\tAllSubs\tFrequency")


def write_reditools(rows):
    fd, path = tempfile.mkstemp(suffix=".output")
    os.close(fd)
    with open(path, "w") as fh:
        fh.write(HEADER + "\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    return path


class TestParseCounts(unittest.TestCase):
    def test_ref_A_edited_is_G_count(self):
        p = write_reditools([
            ["chr12", "6534550", "A", "2", "1879", "35.16", "[1878, 0, 1, 0]", "AG", "0.00"],
        ])
        counts = b.parse_reditools_counts(p)
        os.unlink(p)
        self.assertEqual(counts[("chr12", "6534550")], (1, 1879))  # G count, coverage

    def test_ref_T_edited_is_C_count(self):
        p = write_reditools([
            ["chr1", "500", "T", "2", "40", "35.0", "[0, 7, 0, 33]", "TC", "0.18"],
        ])
        counts = b.parse_reditools_counts(p)
        os.unlink(p)
        self.assertEqual(counts[("chr1", "500")], (7, 40))  # C count, coverage

    def test_non_ai_ref_skipped(self):
        p = write_reditools([
            ["chr1", "500", "C", "2", "40", "35.0", "[0, 33, 0, 7]", "CT", "0.18"],
        ])
        counts = b.parse_reditools_counts(p)
        os.unlink(p)
        self.assertEqual(counts, {})


class TestMatrixIntegerExact(unittest.TestCase):
    def test_common_sites_and_integer_cells(self):
        # Two WT + two KO samples; site (chr1,100) covered in all, (chr1,200) only in s1
        s1 = write_reditools([
            ["chr1", "100", "A", "2", "10", "35", "[8, 0, 2, 0]", "AG", "0.20"],
            ["chr1", "200", "A", "2", "10", "35", "[9, 0, 1, 0]", "AG", "0.10"],
        ])
        s2 = write_reditools([["chr1", "100", "A", "2", "20", "35", "[18, 0, 2, 0]", "AG", "0.10"]])
        s3 = write_reditools([["chr1", "100", "A", "2", "30", "35", "[20, 0, 10, 0]", "AG", "0.33"]])
        s4 = write_reditools([["chr1", "100", "A", "2", "40", "35", "[35, 0, 5, 0]", "AG", "0.12"]])
        out = tempfile.mkstemp(suffix=".tsv")[1]
        sys.argv = ["build", "--inputs", s1, s2, s3, s4,
                    "--sample-names", "WT_c1", "WT_c2", "KO_c1", "KO_c2",
                    "--output", out]
        b.main()
        lines = open(out).read().splitlines()
        for p in (s1, s2, s3, s4, out):
            os.unlink(p)
        self.assertEqual(lines[0], "chrom\tpos\tWT_c1\tWT_c2\tKO_c1\tKO_c2")
        # Only (chr1,100) is common to all four; counts are exact integers "edited,total"
        self.assertEqual(len(lines), 2)
        self.assertEqual(lines[1], "chr1\t100\t2,10\t2,20\t10,30\t5,40")


if __name__ == "__main__":
    unittest.main()
