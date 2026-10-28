import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audit"))
import prove  # noqa: E402

CPP = """int TView::grow(int x)
{
    int limit = 4096;
    return x + limit + 'a';
}
int TView::other() { return 7777; }
"""


def make_allowed(root):
    os.makedirs(os.path.join(root, "src"))
    with open(os.path.join(root, "src", "v.cpp"), "w") as fh:
        fh.write(CPP)
    with open(os.path.join(root, "allowed.txt"), "w") as fh:
        fh.write("magiblot/tvision:source/v.cpp\tsrc/v.cpp\n")
    return prove.Allowed(root)


def match(tokens):
    return {"tokens": [list(t) for t in tokens]}


class TranslationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.allowed = make_allowed(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, tokens, proof):
        return prove.check_proof(match(tokens), proof, self.allowed, set())

    def test_holds(self):
        toks = [("i", "tview"), ("p", "::"), ("i", "grow"), ("l", "n4096"), ("l", "n97"), ("w", "return")]
        ok, why = self.check(toks, "translation magiblot/tvision:source/v.cpp:1-4")
        self.assertTrue(ok, why)

    def test_identifier_outside_the_lines(self):
        ok, why = self.check([("i", "other")], "translation magiblot/tvision:source/v.cpp:1-4")
        self.assertFalse(ok)
        self.assertIn("other", why)

    def test_literal_outside_the_lines(self):
        ok, why = self.check([("l", "n7777")], "translation magiblot/tvision:source/v.cpp:1-4")
        self.assertFalse(ok)
        self.assertTrue(self.check([("l", "n7777")], "translation magiblot/tvision:source/v.cpp:6-6")[0])

    def test_several_locations(self):
        toks = [("i", "grow"), ("i", "other")]
        proof = "translation magiblot/tvision:source/v.cpp:1-1,magiblot/tvision:source/v.cpp:6-6"
        self.assertTrue(self.check(toks, proof)[0])

    def test_predeclared_and_keywords_need_no_source(self):
        toks = [("i", "result"), ("i", "inc"), ("w", "begin"), ("p", ";"), ("i", "integer")]
        self.assertTrue(self.check(toks, "translation magiblot/tvision:source/v.cpp:1-1")[0])

    def test_missing_file_and_bad_locations(self):
        self.assertFalse(self.check([("p", ";")], "translation magiblot/tvision:source/none.cpp:1-4")[0])
        self.assertFalse(self.check([("p", ";")], "translation other/source:v.cpp:1-4")[0])
        self.assertFalse(self.check([("p", ";")], "translation")[0])

    def test_unknown_proof(self):
        self.assertFalse(self.check([("p", ";")], "trust me")[0])


class StandardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        facts = os.path.join(self.tmp.name, "facts", "charsets")
        os.makedirs(facts)
        with open(os.path.join(facts, "CP1.TXT"), "w") as fh:
            fh.write("# table\n0x80\t0x00C7\t#CAPITAL C\n0x81\t0x00FC\t#SMALL U\n")
        with open(os.path.join(facts, "T.ucm"), "w") as fh:
            fh.write("CHARMAP\n<U20AC> \\xD5 |0\nEND CHARMAP\n")
        self.allowed = prove.Allowed(None, os.path.join(self.tmp.name, "facts"))

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, tokens, proof="standard charsets/CP1.TXT"):
        return prove.check_proof(match(tokens), proof, self.allowed, set())

    def test_holds(self):
        toks = [("w", "const"), ("i", "word"), ("p", "="), ("l", "n199"), ("p", ","), ("l", "n252")]
        ok, why = self.check(toks)
        self.assertTrue(ok, why)

    def test_literal_missing(self):
        ok, why = self.check([("l", "n199"), ("l", "n1234")])
        self.assertFalse(ok)
        self.assertIn("literal", why)

    def test_unknown_file(self):
        self.assertFalse(self.check([("p", ";")], "standard charsets/NONE.TXT")[0])
        self.assertFalse(self.check([("p", ";")], "standard charsets/CP1.TXT,charsets/NONE.TXT")[0])
        self.assertFalse(self.check([("p", ";")], "standard")[0])

    def test_identifier_that_is_not_a_keyword(self):
        ok, why = self.check([("i", "cp437"), ("l", "n199")])
        self.assertFalse(ok)
        self.assertIn("cp437", why)

    def test_several_files_and_ucm(self):
        toks = [("l", "n199"), ("l", "n8364"), ("l", "n213")]
        self.assertTrue(self.check(toks, "standard charsets/CP1.TXT,charsets/T.ucm")[0])
        self.assertFalse(self.check(toks)[0])


class ApiTests(unittest.TestCase):
    NAMES = {"tview", "draw"}

    def check(self, tokens, proof="api"):
        return prove.check_proof(match(tokens), proof, prove.Allowed(), self.NAMES)

    def test_names_keywords_punctuation(self):
        self.assertTrue(self.check([("i", "tview"), ("p", "."), ("i", "draw"), ("w", "end"), ("p", ";")])[0])

    def test_unlisted_name(self):
        self.assertFalse(self.check([("i", "other")])[0])

    def test_no_literal(self):
        self.assertFalse(self.check([("l", "n1")])[0])

    def test_no_argument(self):
        self.assertFalse(self.check([("p", ";")], "api x")[0])


class FilesTests(unittest.TestCase):
    def test_api_names_come_from_backticks(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "api.md")
            with open(p, "w") as fh:
                fh.write("Names: `TView.Draw` and `Create`, but not plain words.\n")
            self.assertEqual(prove.api_names(p), {"tview", "draw", "create"})
            self.assertEqual(prove.api_names(os.path.join(d, "none.md")), set())

    def test_load_proofs(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "proofs.txt")
            with open(p, "w") as fh:
                fh.write("# comment\n\nraw\tabc\ta.pas\tapi\nbroken line\n")
            got = prove.load_proofs(p)
            self.assertEqual(got[0], (3, "raw", "abc", "a.pas", "api"))
            self.assertIsNone(got[1][1])

    def test_facts_are_allowed_files(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "facts"))
            with open(os.path.join(d, "facts", "x.md"), "w") as fh:
                fh.write("code 1234\n")
            a = prove.Allowed(None, os.path.join(d, "facts"))
            self.assertIn("facts:x.md", a.files)
            self.assertIsNotNone(a.tokens("facts:x.md"))


if __name__ == "__main__":
    unittest.main()
