import os
import sys
import unittest

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"))

import mpileup_to_candidates as m  # noqa: E402

HI = chr(33 + 40)  # high base quality (~Q40)
LO = chr(33 + 5)   # low base quality  (~Q5)


def quals(n, ch=HI):
    return ch * n


class TestParseSite(unittest.TestCase):
    def test_ref_match_forward_and_reverse(self):
        # 3 forward ref matches, 2 reverse ref matches
        fwd, rev = m.parse_site("...,,", quals(5), "A", 30)
        self.assertEqual(fwd["A"], 3)
        self.assertEqual(rev["A"], 2)

    def test_mismatch_strand_case(self):
        # uppercase G = forward-strand mismatch; lowercase g = reverse
        fwd, rev = m.parse_site("GGg", quals(3), "A", 30)
        self.assertEqual(fwd["G"], 2)
        self.assertEqual(rev["G"], 1)

    def test_base_quality_filter(self):
        # two Gs, one high-qual one low-qual -> only the high-qual one counts
        fwd, rev = m.parse_site("GG", HI + LO, "A", 30)
        self.assertEqual(fwd["G"], 1)

    def test_read_start_and_mapqual_char_skipped(self):
        # '^' + mapqual char then a base; the mapqual char must not consume a qual
        fwd, rev = m.parse_site("^IG", quals(1), "A", 30)
        self.assertEqual(fwd["G"], 1)

    def test_indel_does_not_consume_quality(self):
        # ref match, then a +2 insertion (AC), then another ref match.
        # Two base-consuming symbols -> two quality chars.
        fwd, rev = m.parse_site(".+2AC.", quals(2), "A", 30)
        self.assertEqual(fwd["A"], 2)

    def test_deletion_placeholder_consumes_quality(self):
        fwd, rev = m.parse_site(".*.", quals(3), "A", 30)
        self.assertEqual(fwd["A"], 2)


class TestIterCandidates(unittest.TestCase):
    def _rows(self, lines, min_cov=5, min_alt=2, min_bq=30):
        return list(m.iter_candidates(lines, min_cov, min_alt, min_bq))

    def test_ai_forward_strand_from_substitution(self):
        # ref A, 6 A + 4 G -> cov 10, alt G count 4 -> A>G candidate, strand '+'
        line = "chr1\t100\tA\t10\t......GGGG\t" + quals(10)
        rows = self._rows([line])
        self.assertEqual(len(rows), 1)
        chrom, s0, e1, ref, alt, cov, ac, fc, rc, strand = rows[0]
        self.assertEqual((chrom, s0, e1, ref, alt), ("chr1", 99, 100, "A", "G"))
        self.assertEqual((cov, ac), (10, 4))
        self.assertEqual(strand, "+")

    def test_ai_reverse_strand_tc(self):
        # ref T, 5 T + 3 C -> T>C candidate, strand '-'
        line = "chr1\t200\tT\t8\t.....ccc\t" + quals(8)
        rows = self._rows([line])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][3:5], ("T", "C"))
        self.assertEqual(rows[0][-1], "-")

    def test_non_ai_substitution_has_dot_strand(self):
        # ref A, alt C (A>C, not the A>I class) -> strand '.'
        line = "chr1\t300\tA\t10\t......CCCC\t" + quals(10)
        rows = self._rows([line])
        self.assertEqual(rows[0][4], "C")
        self.assertEqual(rows[0][-1], ".")

    def test_min_alt_reads_floor(self):
        # only 1 G read -> below min_alt=2 -> dropped (the explosion guard)
        line = "chr1\t100\tA\t10\t.........G\t" + quals(10)
        self.assertEqual(self._rows([line]), [])

    def test_min_coverage_floor(self):
        # cov 4 < min_cov 5 -> dropped even with enough alt reads
        line = "chr1\t100\tA\t4\t..GG\t" + quals(4)
        self.assertEqual(self._rows([line]), [])

    def test_multiple_alts_emitted_separately(self):
        # ref A with both G and C alts above floor -> two rows
        line = "chr1\t100\tA\t10\t..GGGCCC.G\t" + quals(10)
        rows = self._rows([line])
        alts = sorted(r[4] for r in rows)
        self.assertEqual(alts, ["C", "G"])

    def test_non_acgt_ref_skipped(self):
        line = "chr1\t100\tN\t10\t..GGGGGGGG\t" + quals(10)
        self.assertEqual(self._rows([line]), [])


if __name__ == "__main__":
    unittest.main()
