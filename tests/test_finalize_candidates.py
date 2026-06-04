import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"))

import finalize_candidates as fc  # noqa: E402


class TestResolve(unittest.TestCase):
    def test_ai_substitution_wins_over_annotation(self):
        # A>G fixes '+' even if annotation says '-'
        label, strand = fc.resolve("+", {"-"}, ["GENE1"])
        self.assertEqual(strand, "+")
        self.assertEqual(label, "GENE1")

    def test_non_ai_uses_single_gene_strand(self):
        label, strand = fc.resolve(".", {"-"}, ["GENE2"])
        self.assertEqual((label, strand), ("GENE2", "-"))

    def test_non_ai_intergenic_is_hash_and_Inte(self):
        label, strand = fc.resolve(".", set(), [])
        self.assertEqual((label, strand), ("Inte", "#"))

    def test_non_ai_both_strands_is_hash(self):
        # genic but ambiguous (overlapping +/- genes) -> '#', keeps a gene label
        label, strand = fc.resolve(".", {"+", "-"}, ["GENE3"])
        self.assertEqual(strand, "#")
        self.assertEqual(label, "GENE3")


class TestEndToEnd(unittest.TestCase):
    def test_views_written(self):
        d = tempfile.mkdtemp()
        cand = os.path.join(d, "candidates.bed")
        gene = os.path.join(d, "gene.tsv")
        dbsnp = os.path.join(d, "dbsnp.tsv")
        giremi = os.path.join(d, "giremi.snv")
        editp = os.path.join(d, "editpredict.pos")

        # Two candidates: an A>G edit (genic +) and an A>C non-edit (intergenic).
        with open(cand, "w") as fh:
            fh.write("chr1\t99\t100\tA\tG\t10\t4\t4\t0\t+\n")
            fh.write("chr1\t199\t200\tA\tC\t10\t3\t3\t0\t.\n")
        # gene -loj: A>G overlaps GENEX(+); A>C no overlap (sentinels)
        with open(gene, "w") as fh:
            fh.write("chr1\t99\t100\tA\tG\t10\t4\t4\t0\t+\t"
                     "chr1\t50\t500\tGENEX\tprotein_coding\t+\n")
            fh.write("chr1\t199\t200\tA\tC\t10\t3\t3\t0\t.\t"
                     ".\t-1\t-1\t.\t.\t.\n")
        # dbsnp -c: A>G is a known SNP (count 1); A>C is not (0)
        with open(dbsnp, "w") as fh:
            fh.write("chr1\t99\t100\tA\tG\t10\t4\t4\t0\t+\t1\n")
            fh.write("chr1\t199\t200\tA\tC\t10\t3\t3\t0\t.\t0\n")

        sys.argv = ["finalize", "--candidates", cand, "--gene-intersect", gene,
                    "--dbsnp-intersect", dbsnp, "--giremi-out", giremi,
                    "--editpredict-out", editp]
        fc.main()

        giremi_rows = [l.split("\t") for l in open(giremi).read().splitlines()]
        # Both candidates appear in the GIREMI list (all substitution types).
        self.assertEqual(len(giremi_rows), 2)
        self.assertEqual(giremi_rows[0], ["chr1", "99", "100", "GENEX", "1", "+"])
        self.assertEqual(giremi_rows[1], ["chr1", "199", "200", "Inte", "0", "#"])

        # Only the A>I site is in the EditPredict positions view.
        editp_rows = open(editp).read().splitlines()
        self.assertEqual(editp_rows, ["chr1\t100"])


if __name__ == "__main__":
    unittest.main()
