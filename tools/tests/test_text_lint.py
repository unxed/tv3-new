import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import text_lint  # noqa: E402

# Words that the rule forbids are put together here, so that this file keeps to the rule too.
WT = "clau" + "de"
WA = "age" + "nt"
WC = "ch" + "at"
WR = "re" + "write"
WO = "owner " + "decided"
WL = "luno" + "bot"
CYR = "\\u043f\\u0440\\u0438\\u0432\\u0435\\u0442".encode("ascii").decode("unicode_escape")
CYR_WA = "\\u0430\\u0433\\u0435\\u043d\\u0442".encode("ascii").decode("unicode_escape")


def rules(text, **kw):
    return [f["rule"] for f in text_lint.check_text("x", text, **kw)]


class NeutralTests(unittest.TestCase):
    def test_plain_text_is_clean(self):
        self.assertEqual(rules("A view draws itself into a buffer."), [])

    def test_forbidden_words(self):
        for word in (WT, WA, WA + "s", WC, WR, WR + "ing", WO, WL,
                     "son" + "net", "op" + "us", "cod" + "ex"):
            self.assertTrue(rules("some " + word + " here"), word)

    def test_case_insensitive(self):
        self.assertTrue(rules(WT.upper() + " said"))

    def test_whole_words(self):
        self.assertEqual(rules("a magazine of chatter and agentless parts"), [])
        self.assertEqual(rules("the " + WC + "ter"), [])

    def test_rules_file_name_is_allowed(self):
        self.assertEqual(rules("see " + WT.upper() + ".md for the rules"), [])
        self.assertTrue(rules(WT.upper() + " wrote it"))

    def test_russian_words(self):
        self.assertTrue(rules(CYR_WA, allow_cyrillic=True))

    def test_cyrillic(self):
        self.assertIn("cyrillic", rules(CYR))
        self.assertEqual(rules(CYR, allow_cyrillic=True), [])

    def test_replacement_character(self):
        self.assertIn("replacement character", rules("a\\ufffdb".encode("ascii").decode("unicode_escape")))


class FileTests(unittest.TestCase):
    def test_bom(self):
        f = text_lint.check_bytes("a.txt", b"\xef\xbb\xbfabc")
        self.assertEqual(f[0]["rule"], "byte order mark")

    def test_not_utf8(self):
        f = text_lint.check_bytes("a.txt", b"\xff\xfe\xfa")
        self.assertEqual(f[0]["rule"], "not UTF-8")

    def test_cyrillic_only_in_tests(self):
        data = CYR.encode("utf-8")
        self.assertTrue(text_lint.check_bytes("docs/a.md", data))
        self.assertEqual(text_lint.check_bytes("tests/a.pas", data), [])
        self.assertEqual(text_lint.check_bytes("tools/audit/facts/a.md", data), [])

    def test_self_is_exempt(self):
        data = (WT + " " + WA).encode("utf-8")
        self.assertEqual(text_lint.check_bytes("tools/text_lint.py", data), [])
        self.assertTrue(text_lint.check_bytes("tools/other.py", data))

    def test_report_quotes_are_exempt(self):
        data = ("text check: commit 0123456789ab: neutral: tool name " + WL).encode("utf-8")
        self.assertEqual(text_lint.check_bytes("VERDICT.md", data), [])
        self.assertTrue(text_lint.check_bytes("docs/VERDICT.md", data))
        self.assertEqual(text_lint.check_bytes("VERDICT.md", b"\xef\xbb\xbfx")[0]["rule"], "byte order mark")
        self.assertEqual(text_lint.check_bytes("VERDICT.md", b"\xff\xfe")[0]["rule"], "not UTF-8")

    def test_names(self):
        self.assertEqual(text_lint.check_name(WT.upper() + ".md"), [])
        self.assertTrue(text_lint.check_name("docs/" + WA + ".md"))
        self.assertTrue(text_lint.check_name("docs/" + CYR + ".md"))


class RepoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.git("init", "-q")
        self.git("config", "user.name", "t")
        self.git("config", "user.email", "t@example.com")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        subprocess.run(["git", "-C", self.dir] + list(args), check=True, stdout=subprocess.PIPE)

    def commit(self, name, text, message):
        with open(os.path.join(self.dir, name), "w") as fh:
            fh.write(text)
        self.git("add", name)
        self.git("commit", "-q", "-m", message)

    def test_clean_repository(self):
        self.commit("a.md", "Hello.\n", "Add a")
        r = text_lint.run(self.dir, "HEAD")
        self.assertTrue(r["pass"])
        self.assertEqual(r["files"], 1)
        self.assertEqual(r["commits"], 1)

    def test_bad_file(self):
        self.commit("a.md", "The " + WA + " did it.\n", "Add a")
        r = text_lint.run(self.dir)
        self.assertFalse(r["pass"])
        self.assertEqual(r["findings"][0]["where"], "a.md")

    def test_bad_commit_message(self):
        self.commit("a.md", "Hello.\n", "Add a, " + WR + " of b")
        self.commit("b.md", "Hello.\n", "Add b")
        r = text_lint.run(self.dir, "HEAD")
        self.assertFalse(r["pass"])
        self.assertEqual(r["commits"], 2)
        self.assertTrue(r["findings"][0]["where"].startswith("commit "))

    def test_assisted_by_trailer_is_not_checked(self):
        self.commit("a.md", "Hello.\n", "Add a\n\nAssisted-by: " + WA + " model")
        r = text_lint.run(self.dir, "HEAD")
        self.assertTrue(r["pass"])

    def test_other_trailer_is_checked(self):
        self.commit("a.md", "Hello.\n", "Add a\n\nCo-Authored-By: " + WA + " model")
        r = text_lint.run(self.dir, "HEAD")
        self.assertFalse(r["pass"])

    def test_range_limits_messages(self):
        self.commit("a.md", "Hello.\n", "Add a, " + WR + " of b")
        self.commit("b.md", "Hello.\n", "Add b")
        r = text_lint.run(self.dir, "HEAD~1..HEAD")
        self.assertTrue(r["pass"])
        self.assertEqual(r["commits"], 1)

    def test_given_text(self):
        self.commit("a.md", "Hello.\n", "Add a")
        r = text_lint.run(self.dir, None, [("title", "Add " + WT)])
        self.assertFalse(r["pass"])


if __name__ == "__main__":
    unittest.main()
