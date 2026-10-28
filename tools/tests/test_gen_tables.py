import os
import subprocess
import sys
import tempfile
import unittest

TOOLS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, TOOLS)
import gen_tables  # noqa: E402

GLYPHS = {
    0x00: 0x0000, 0x01: 0x263A, 0x02: 0x263B, 0x03: 0x2665, 0x04: 0x2666, 0x05: 0x2663, 0x06: 0x2660,
    0x07: 0x2022, 0x08: 0x25D8, 0x09: 0x25CB, 0x0A: 0x25D9, 0x0B: 0x2642, 0x0C: 0x2640, 0x0D: 0x266A,
    0x0E: 0x266B, 0x0F: 0x263C, 0x10: 0x25BA, 0x11: 0x25C4, 0x12: 0x2195, 0x13: 0x203C, 0x14: 0x00B6,
    0x15: 0x00A7, 0x16: 0x25AC, 0x17: 0x21A8, 0x18: 0x2191, 0x19: 0x2193, 0x1A: 0x2192, 0x1B: 0x2190,
    0x1C: 0x221F, 0x1D: 0x2194, 0x1E: 0x25B2, 0x1F: 0x25BC, 0x7F: 0x2302,
}


def by_name(tables):
    return dict((name, values) for name, _, values in tables)


class ParseTests(unittest.TestCase):
    def test_txt_mapped(self):
        self.assertEqual(gen_tables.parse_txt_line("0x80\t0x20AC\t#EURO SIGN"), (0x80, 0x20AC))
        self.assertEqual(gen_tables.parse_txt_line("0x0a\t0x000a\t#LINE FEED"), (0x0A, 0x000A))

    def test_txt_undefined(self):
        self.assertEqual(gen_tables.parse_txt_line("0x81\t      \t#UNDEFINED"), (0x81, None))
        self.assertEqual(gen_tables.parse_txt_line("0x81\t#UNDEFINED"), (0x81, None))

    def test_txt_blank_and_comment(self):
        self.assertIsNone(gen_tables.parse_txt_line(""))
        self.assertIsNone(gen_tables.parse_txt_line("# Name: table"))
        self.assertIsNone(gen_tables.parse_txt_line("\x1a"))

    def test_txt_bad(self):
        for line in ("0x8\t0x20AC", "80\t20AC", "0x80\t0x20AC\t0x20AD", "0x80 0xZZZZ", "text"):
            with self.assertRaises(ValueError):
                gen_tables.parse_txt_line(line)

    def test_ucm_roundtrip(self):
        self.assertEqual(gen_tables.parse_ucm_line("<U00C7> \\x80 |0"), (0x80, 0x00C7))
        self.assertEqual(gen_tables.parse_ucm_line("<U20AC> \\xD5 |0 # comment"), (0xD5, 0x20AC))

    def test_ucm_other_lines(self):
        self.assertIsNone(gen_tables.parse_ucm_line("<U00C7> \\x80 |1"))
        self.assertIsNone(gen_tables.parse_ucm_line("<U00C7> \\x80 |3"))
        self.assertIsNone(gen_tables.parse_ucm_line("<U3000> \\xA1\\xA1 |0"))
        self.assertIsNone(gen_tables.parse_ucm_line(""))
        self.assertIsNone(gen_tables.parse_ucm_line("# comment"))

    def test_ucm_bad(self):
        for line in ("<U00C7> 0x80 |0", "<U00C7> \\x80", "U00C7 \\x80 |0", "<UZZZZ> \\x80 |0"):
            with self.assertRaises(ValueError):
                gen_tables.parse_ucm_line(line)


class FileTests(unittest.TestCase):
    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(gen_tables.TableError):
                gen_tables.read_mapping(d, 437)

    def test_bad_line(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "CP437.TXT"), "wb") as fh:
                fh.write(b"0x80\t0x00C7\t#X\nbroken line\n")
            with self.assertRaises(gen_tables.TableError):
                gen_tables.read_mapping(d, 437)

    def test_duplicate_byte(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "CP437.TXT"), "wb") as fh:
                fh.write(b"0x80\t0x00C7\t#X\n0x80\t0x00C8\t#Y\n")
            with self.assertRaises(gen_tables.TableError):
                gen_tables.read_mapping(d, 437)

    def test_ucm_without_charmap(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "ibm-858_P100-1997.ucm"), "wb") as fh:
                fh.write(b"<code_set_name> \"x\"\n")
            with self.assertRaises(gen_tables.TableError):
                gen_tables.read_mapping(d, 858)

    def test_source_names(self):
        self.assertEqual(gen_tables.source_name(437), "CP437.TXT")
        self.assertEqual(gen_tables.source_name(1251), "CP1251.TXT")
        self.assertEqual(gen_tables.source_name(20866), "KOI8-R.TXT")
        self.assertEqual(gen_tables.source_name(21866), "KOI8-U.TXT")
        self.assertEqual(gen_tables.source_name(10000), "ROMAN.TXT")
        self.assertEqual(gen_tables.source_name(28591), "8859-1.TXT")
        self.assertEqual(gen_tables.source_name(28601), "8859-11.TXT")
        self.assertEqual(gen_tables.source_name(28606), "8859-16.TXT")
        self.assertEqual(gen_tables.source_name(720), "ibm-720_P100-1997.ucm")
        self.assertEqual(gen_tables.source_name(858), "ibm-858_P100-1997.ucm")
        self.assertEqual(gen_tables.source_name(1125), "ibm-1125_P100-1997.ucm")


class TableRuleTests(unittest.TestCase):
    def test_undefined_bytes_of_a_synthetic_mapping(self):
        cp = gen_tables.cp_table({0x80: 0x00C7})
        self.assertEqual(cp[0x80], 0x00C7)
        self.assertEqual(cp[0x81], 0)
        st = gen_tables.set_table({0x80: 0x00C7})
        self.assertEqual(st[0x80], 0x00C7)
        self.assertEqual(st[0x81], 0)
        self.assertEqual(cp[0], 0)
        self.assertEqual(st[0], 0)

    def test_synthetic_low_half_is_not_taken_from_the_mapping(self):
        cp = gen_tables.cp_table({0x41: 0x1234, 0x01: 0x0001})
        self.assertEqual(cp[0x41], 0x41)
        self.assertEqual(cp[0x01], 0x263A)
        st = gen_tables.set_table({0x41: 0x1234})
        self.assertEqual(st[0x41], 0x41)


class RealCpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = gen_tables.cp_tables()
        cls.by_name = by_name(cls.tables)

    def test_count_and_order(self):
        names = [n for n, _, _ in self.tables]
        self.assertEqual(names, ["Cp437", "Cp737", "Cp775", "Cp850", "Cp852", "Cp855", "Cp857", "Cp858",
                                 "Cp860", "Cp861", "Cp862", "Cp863", "Cp864", "Cp865", "Cp866", "Cp869",
                                 "Cp1125"])

    def test_size_and_range(self):
        for name, _, values in self.tables:
            self.assertEqual(len(values), 256, name)
            for v in values:
                self.assertTrue(0 <= v <= 0xFFFF, name)

    def test_ascii_range(self):
        for name, _, values in self.tables:
            for b in range(0x20, 0x7F):
                self.assertEqual(values[b], b, "%s %02X" % (name, b))

    def test_glyphs(self):
        for name, _, values in self.tables:
            for b, u in GLYPHS.items():
                self.assertEqual(values[b], u, "%s %02X" % (name, b))

    def test_high_half_values(self):
        self.assertEqual(self.by_name["Cp437"][0x80], 0x00C7)
        self.assertEqual(self.by_name["Cp437"][0xE1], 0x00DF)
        self.assertEqual(self.by_name["Cp437"][0xFF], 0x00A0)
        self.assertEqual(self.by_name["Cp866"][0x80], 0x0410)
        self.assertEqual(self.by_name["Cp1125"][0x80], 0x0410)
        self.assertEqual(self.by_name["Cp858"][0x80], 0x00C7)

    def test_zero_only_at_byte_zero_in_the_low_half(self):
        for name, _, values in self.tables:
            for b in range(1, 0x80):
                self.assertNotEqual(values[b], 0, "%s %02X" % (name, b))

    def test_zero_in_the_high_half_means_undefined(self):
        for ident in gen_tables.CP_IDS:
            mapping = gen_tables.read_mapping(gen_tables.FACTS, ident)
            values = self.by_name["Cp%d" % ident]
            for b in range(0x80, 0x100):
                self.assertEqual(values[b], mapping.get(b, 0), "%d %02X" % (ident, b))
                if values[b] == 0:
                    self.assertNotIn(b, mapping, "%d %02X" % (ident, b))

    def test_undefined_bytes_of_pages(self):
        undefined = {
            "Cp857": [0xD5, 0xE7, 0xF2],
            "Cp864": [0x9B, 0x9C, 0x9F, 0xA6, 0xA7, 0xFF],
            "Cp869": [0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x87, 0x93, 0x94],
        }
        for name, bytes_ in undefined.items():
            for b in bytes_:
                self.assertEqual(self.by_name[name][b], 0, "%s %02X" % (name, b))


class RealSetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = gen_tables.set_tables()
        cls.by_name = by_name(cls.tables)

    def test_count_and_order(self):
        self.assertEqual(len(self.tables), 46)
        self.assertEqual(len(gen_tables.SET_IDS), 46)
        self.assertEqual([n for n, _, _ in self.tables], ["Set%d" % i for i in gen_tables.SET_IDS])
        self.assertEqual(self.tables[0][0], "Set437")
        self.assertEqual(self.tables[-1][0], "Set10000")

    def test_size_and_range(self):
        for name, _, values in self.tables:
            self.assertEqual(len(values), 256, name)
            for v in values:
                self.assertTrue(0 <= v <= 0xFFFF, name)

    def test_low_half_is_identity(self):
        for name, _, values in self.tables:
            self.assertEqual(values[:128], list(range(128)), name)

    def test_latin1_is_identity(self):
        self.assertEqual(self.by_name["Set28591"], list(range(256)))

    def test_undefined_bytes(self):
        self.assertEqual(self.by_name["Set1252"][0x81], 0)
        self.assertEqual(self.by_name["Set874"][0x81], 0)
        self.assertEqual(self.by_name["Set1251"][0x98], 0)

    def test_zero_in_the_high_half_means_undefined(self):
        for ident in gen_tables.SET_IDS:
            mapping = gen_tables.read_mapping(gen_tables.FACTS, ident)
            values = self.by_name["Set%d" % ident]
            for b in range(0x80, 0x100):
                self.assertEqual(values[b], mapping.get(b, 0), "%d %02X" % (ident, b))
                if values[b] == 0:
                    self.assertNotIn(b, mapping, "%d %02X" % (ident, b))
        self.assertEqual(self.by_name["Set1252"][0x80], 0x20AC)

    def test_high_half_values(self):
        self.assertEqual(self.by_name["Set437"][0x80], 0x00C7)
        self.assertEqual(self.by_name["Set858"][0x80], 0x00C7)
        self.assertEqual(self.by_name["Set1125"][0x80], 0x0410)
        self.assertEqual(self.by_name["Set1251"][0xC0], 0x0410)
        self.assertEqual(self.by_name["Set20866"][0xC1], 0x0430)
        self.assertEqual(self.by_name["Set10000"][0x80], 0x00C4)

    def test_every_file_exists(self):
        for ident in gen_tables.SET_IDS:
            path = os.path.join(gen_tables.FACTS, gen_tables.source_name(ident))
            self.assertTrue(os.path.isfile(path), path)


class OutputTests(unittest.TestCase):
    def test_cp_output(self):
        text = gen_tables.render("cp")
        lines = text.split("\n")
        self.assertEqual(lines[0], "{ Generated by tools/gen_tables.py }")
        self.assertIn("{ " + gen_tables.UNDEFINED_NOTE + " }", lines)
        self.assertNotIn("$FFFD", text)
        self.assertEqual(text.count("array[0..255] of Word"), 17)
        self.assertIn("  Cp437: array[0..255] of Word = (", lines)
        self.assertIn("  Cp1125: array[0..255] of Word = (", lines)
        self.assertTrue(text.endswith("  );\n"))

    def test_sets_output(self):
        text = gen_tables.render("sets")
        lines = text.split("\n")
        self.assertEqual(lines[0], "{ Generated by tools/gen_tables.py }")
        self.assertIn("{ " + gen_tables.UNDEFINED_NOTE + " }", lines)
        self.assertNotIn("$FFFF", text)
        self.assertEqual(text.count("array[0..255] of Word"), 46)
        for ident in gen_tables.SET_IDS:
            self.assertIn("  Set%d: array[0..255] of Word = (" % ident, lines)
            self.assertIn("{ Set%d: %s }" % (ident, gen_tables.source_name(ident)), lines)

    def test_ascii_only(self):
        for kind in ("cp", "sets"):
            gen_tables.render(kind).encode("ascii")

    def test_unknown_kind(self):
        with self.assertRaises(gen_tables.TableError):
            gen_tables.render("other")

    def test_program(self):
        script = os.path.join(TOOLS, "gen_tables.py")
        done = subprocess.run([sys.executable, script, "cp"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(done.returncode, 0)
        self.assertEqual(done.stdout.decode("ascii"), gen_tables.render("cp"))
        bad = subprocess.run([sys.executable, script], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(bad.returncode, 2)


if __name__ == "__main__":
    unittest.main()
