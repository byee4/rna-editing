"""
Unit tests for compare_all_tools.py edit-type filtering (Part A).

  module load python3essential
  python -m unittest tests/test_compare_all_tools.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"
))
import compare_all_tools as cat  # noqa: E402


class EditTypeSetTest(unittest.TestCase):
    def test_ag_includes_reverse_complement_and_arrow_forms(self):
        self.assertEqual(cat.edit_type_set("AG"), {"AG", "TC", "A>G", "T>C"})

    def test_ct(self):
        self.assertEqual(cat.edit_type_set("CT"), {"CT", "GA", "C>T", "G>A"})


class ParserFilteringTest(unittest.TestCase):
    def setUp(self):
        self._saved = cat.EDIT_TYPES

    def tearDown(self):
        cat.EDIT_TYPES = self._saved

    def _write_reditools2(self, tmp):
        # cols: region pos ref strand cov meanQ baseCount allSubs freq
        path = os.path.join(tmp, "rt2.output")
        with open(path, "w") as fh:
            fh.write("chr1\t100\tA\t1\t20\t30\t[0,0,0,0]\tAG\t0.5\n")
            fh.write("chr2\t200\tC\t1\t25\t30\t[0,0,0,0]\tCT\t0.3\n")
        return path

    def test_default_ag_keeps_only_ag(self):
        cat.EDIT_TYPES = cat.edit_type_set("AG")
        with tempfile.TemporaryDirectory() as tmp:
            sites = cat.parse_reditools2(self._write_reditools2(tmp))
        self.assertIn(("chr1", "100"), sites)
        self.assertNotIn(("chr2", "200"), sites)

    def test_ct_keeps_only_ct(self):
        cat.EDIT_TYPES = cat.edit_type_set("CT")
        with tempfile.TemporaryDirectory() as tmp:
            sites = cat.parse_reditools2(self._write_reditools2(tmp))
        self.assertIn(("chr2", "200"), sites)
        self.assertNotIn(("chr1", "100"), sites)


class Jacusa2Call1Test(unittest.TestCase):
    # contig start end name score strand ref bases11(A,C,G,T) info filter
    JAC = (
        "##JACUSA2 call-1\n"
        "#contig\tstart\tend\tname\tscore\tstrand\tref\tbases11\tinfo\tfilter\n"
        "chr1\t100\t101\tvar\t5.5\t+\tA\t2,0,8,0\t*\t*\n"   # A>G  -> AG
        "chr3\t300\t301\tvar\t9.9\t+\tC\t0,5,0,5\t*\t*\n"   # C>T  -> not AG
    )

    def setUp(self):
        self._saved_types = cat.EDIT_TYPES
        self._saved_filter = cat.JACUSA2_CALL1_FILTER
        cat.EDIT_TYPES = cat.edit_type_set("AG")

    def tearDown(self):
        cat.EDIT_TYPES = self._saved_types
        cat.JACUSA2_CALL1_FILTER = self._saved_filter

    def _write(self, tmp):
        path = os.path.join(tmp, "WT_clone1.out")
        with open(path, "w") as fh:
            fh.write(self.JAC)
        return path

    def test_coverage_fraction_score_from_bases11(self):
        cat.JACUSA2_CALL1_FILTER = "edit_type"
        with tempfile.TemporaryDirectory() as tmp:
            sites = cat.parse_jacusa2_call1(self._write(tmp))
        self.assertEqual(sites[("chr1", "101")], (10.0, 0.8, 5.5))

    def test_edit_type_filter_drops_non_ag(self):
        cat.JACUSA2_CALL1_FILTER = "edit_type"
        with tempfile.TemporaryDirectory() as tmp:
            sites = cat.parse_jacusa2_call1(self._write(tmp))
        self.assertIn(("chr1", "101"), sites)
        self.assertNotIn(("chr3", "301"), sites)

    def test_unfiltered_keeps_all_sites(self):
        cat.JACUSA2_CALL1_FILTER = "unfiltered"
        with tempfile.TemporaryDirectory() as tmp:
            sites = cat.parse_jacusa2_call1(self._write(tmp))
        self.assertIn(("chr1", "101"), sites)
        self.assertIn(("chr3", "301"), sites)


if __name__ == "__main__":
    unittest.main()
