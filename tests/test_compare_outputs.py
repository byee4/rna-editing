"""
Unit tests for compare_outputs.py (Part B: output-type-aware correlation).

Run with pandas/numpy/scipy available:
  module load python3essential
  python -m unittest tests/test_compare_outputs.py
"""
import os
import sys
import tempfile
import unittest

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"
))
import compare_outputs as co  # noqa: E402


# Shared tiny fixture: 4 positions, 7 tools, aligner "star", one sample.
POSITIONS = ["chr1:100", "chr1:200", "chr1:300", "chr2:100"]
COLS = [
    "reditools.star.WT_s1", "reditools3.star.WT_s1", "red_ml.star.WT_s1",
    "redinet.star.WT_s1", "sprint.star.WT_s1", "bcftools.star.WT_s1",
    "jacusa2.star.all_samples",
]

# rows align to POSITIONS; cols align to COLS
FRAC = [
    [0.2, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0],
    [0.5, 0.6, 0.4, 0.0, 0.0, 0.0, 0.0],
    [0.8, 0.9, 0.0, 0.7, 0.0, 0.0, 0.0],
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
]
SCORE = [
    [0.2, 0.3, 0.0, 0.00, 5.0, 0.0, 0.0],
    [0.5, 0.6, 0.9, 0.00, 0.0, 30.0, 0.0],
    [0.8, 0.9, 0.0, 0.95, 8.0, 0.0, 10.0],
    [0.0, 0.0, 0.0, 0.00, 3.0, 40.0, 0.0],
]
COV = [
    [10, 10, 0, 0, 0, 0, 0],
    [20, 20, 15, 0, 0, 25, 0],
    [40, 40, 0, 30, 0, 0, 0],
    [0, 0, 0, 0, 0, 18, 0],
]

# geneA covers chr1:100,200 ; geneB covers chr1:300 ; geneC covers chr2:100
GTF = (
    'chr1\tsrc\tgene\t1\t250\t.\t+\t.\tgene_id "geneA";\n'
    'chr1\tsrc\tgene\t251\t400\t.\t+\t.\tgene_id "geneB";\n'
    'chr2\tsrc\tgene\t1\t200\t.\t+\t.\tgene_id "geneC";\n'
)


def _write_fixture(tmp):
    mdir = os.path.join(tmp, "matrices")
    os.makedirs(mdir, exist_ok=True)
    for name, vals in [("edit_fraction_matrix.tsv", FRAC),
                       ("tool_score_matrix.tsv", SCORE),
                       ("edit_coverage_matrix.tsv", COV)]:
        df = pd.DataFrame(vals, index=POSITIONS, columns=COLS)
        df.to_csv(os.path.join(mdir, name), sep="\t")
    gtf = os.path.join(tmp, "genes.gtf")
    with open(gtf, "w") as fh:
        fh.write(GTF)
    return mdir, gtf


class StreamRecordsTest(unittest.TestCase):
    def test_presence_and_records(self):
        with tempfile.TemporaryDirectory() as tmp:
            mdir, _ = _write_fixture(tmp)
            data = co.stream_records(mdir, ["star"])
        # reditools called the three chr1 sites only
        self.assertEqual(set(data[("star", "reditools")].keys()),
                         {"chr1:100", "chr1:200", "chr1:300"})
        # sprint presence from score (supporting reads), incl chr2:100
        self.assertEqual(set(data[("star", "sprint")].keys()),
                         {"chr1:100", "chr1:300", "chr2:100"})
        # record = (frac, cov, score)
        self.assertEqual(data[("star", "reditools")]["chr1:200"], (0.5, 20.0, 0.5))


class GeneIndexTest(unittest.TestCase):
    def test_pos_to_gene(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, gtf = _write_fixture(tmp)
            idx = co.load_gene_index(gtf)
        self.assertEqual(co.pos_to_gene(idx, "chr1:100"), "geneA")
        self.assertEqual(co.pos_to_gene(idx, "chr1:300"), "geneB")
        self.assertEqual(co.pos_to_gene(idx, "chr2:100"), "geneC")
        self.assertIsNone(co.pos_to_gene(idx, "chr3:50"))


class ValueForTest(unittest.TestCase):
    def test_read_count_uses_edited_reads_for_reditools(self):
        # frac*cov
        self.assertEqual(co.value_for("reditools", "read_count", (0.5, 20.0, 0.5)), 10.0)
        # sprint uses score (supporting reads)
        self.assertEqual(co.value_for("sprint", "read_count", (0.0, 0.0, 8.0)), 8.0)

    def test_quality_score_uses_score(self):
        self.assertEqual(co.value_for("bcftools", "quality_score", (0.0, 25.0, 30.0)), 30.0)


class EndToEndTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        mdir, gtf = _write_fixture(self.tmp.name)
        self.out = os.path.join(self.tmp.name, "out")
        data = co.stream_records(mdir, ["star"])
        gene_index = co.load_gene_index(gtf)
        co.process_aligner("star", data, gene_index, self.out, min_tools=2)

    def tearDown(self):
        self.tmp.cleanup()

    def _read(self, sub, name):
        return pd.read_csv(os.path.join(self.out, sub, name), sep="\t", index_col=0)

    def test_jaccard(self):
        jac = self._read("intersect", "tool_jaccard_star.tsv")
        self.assertAlmostEqual(jac.loc["reditools", "reditools3"], 1.0)
        cnt = self._read("intersect", "tool_overlap_counts_star.tsv")
        self.assertEqual(int(cnt.loc["reditools", "sprint"]), 2)

    def test_cocall_table(self):
        t = pd.read_csv(os.path.join(self.out, "intersect", "edits_intersect_star.tsv"),
                        sep="\t")
        self.assertEqual(len(t), 4)  # all four positions called by >=2 tools
        r200 = t[t["pos"] == 200].iloc[0]
        self.assertEqual(int(r200["n_tools"]), 4)
        r100 = t[t["pos"] == 100].iloc[0]
        self.assertAlmostEqual(float(r100["reditools"]), 0.2)
        self.assertTrue(np.isnan(float(r100["sprint"])))  # no fraction for sprint

    def test_site_fraction_correlation(self):
        corr = self._read("by_output_type", "per-site-fraction-correlation_star.tsv")
        self.assertAlmostEqual(corr.loc["reditools", "reditools3"], 1.0)
        # red_ml shares only 1 frac>0 site with reditools -> NaN
        self.assertTrue(np.isnan(corr.loc["reditools", "red_ml"]))
        nov = self._read("by_output_type", "per-site-fraction-correlation_noverlap_star.tsv")
        self.assertEqual(int(nov.loc["reditools", "reditools3"]), 3)

    def test_read_count_correlation(self):
        corr = self._read("by_output_type", "read-count-correlation_star.tsv")
        self.assertAlmostEqual(corr.loc["reditools", "reditools3"], 1.0)

    def test_group_score_is_stub(self):
        path = os.path.join(self.out, "by_output_type",
                            "group-or-comparison-score_star.tsv")
        with open(path) as fh:
            first = fh.readline()
        self.assertTrue(first.startswith("#"))  # single-member stub, not a crash


if __name__ == "__main__":
    unittest.main()
