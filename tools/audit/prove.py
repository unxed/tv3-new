#!/usr/bin/env python3
"""Mechanical proofs of audit matches (tools/audit/proofs.txt).

A line of proofs.txt has four tab separated columns: comparison, match id (SHA-256), path, proof.
A proof is one of:
  translation SOURCE:FILE:A-B[,SOURCE:FILE:A-B...]
      SOURCE is magiblot/tvision or magiblot/tvterm. It holds when every identifier and every literal of the
      match occurs among the tokens of those lines of the allowed file (identifiers in any letter case,
      literals by value).
  standard FILE[,FILE...]
      Each FILE is a path relative to tools/audit/facts (for example charsets/CP437.TXT; the logical name
      is facts:FILE). It holds when every literal of the match occurs, by value, among the literals of
      those files (in a ucm file the code points <UXXXX> and the bytes \\xBB count as numbers), and every
      identifier of the match is a keyword or a predeclared name.
  api
      It holds when the match is only keywords, punctuation and names written in backticks in
      docs/API-NAMES.md, and no literal.
Keywords, punctuation and the predeclared identifiers of Pascal (PREDECLARED) need no source.

Usage: prove.py --report audit.json [--corpora DIR] [--proofs FILE] [--api-names FILE]
Prints the verdict on each line of the proofs file; exit code 1 when a proof does not hold.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tokens as T  # noqa: E402

PREDECLARED = frozenset("""
result self exit inc dec ord chr low high length setlength sizeof succ pred true false
integer longint shortint smallint byte word longword cardinal int64 qword uint64 int8 int16 int32 uint8 uint16
uint32 boolean bytebool wordbool longbool char ansichar widechar string ansistring shortstring widestring
unicodestring pchar pansichar pwidechar pointer real single double extended comp currency nativeint nativeuint
ptrint ptruint sizeint
break continue assigned new dispose getmem freemem move fillchar copy pos delete insert abs odd trunc round halt
include exclude create destroy free
""".split())

LOCATION_RE = re.compile(r"^(magiblot/tvision|magiblot/tvterm):(.+):([0-9]+)-([0-9]+)$")
BACKTICK_RE = re.compile(r"`([^`\n]+)`")
WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
UCM_WORD_RE = re.compile(r"^(?:u([0-9a-f]{4,6})|x([0-9a-f]{2}))$")


def read_text(path):
    with open(path, "rb") as fh:
        data = fh.read()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


class Allowed:
    """The allowed sources: logical name -> file."""

    def __init__(self, corpora=None, facts_dir=None):
        self.files = {}
        self._cache = {}
        if corpora:
            listing = os.path.join(corpora, "allowed.txt")
            if os.path.exists(listing):
                with open(listing, encoding="utf-8") as fh:
                    for line in fh:
                        line = line.rstrip("\n")
                        if not line:
                            continue
                        logical, _, rel = line.partition("\t")
                        self.files[logical] = os.path.join(corpora, rel)
        if facts_dir and os.path.isdir(facts_dir):
            for root, _dirs, names in os.walk(facts_dir):
                for name in sorted(names):
                    if name.lower().endswith((".md", ".txt", ".ucm")):
                        full = os.path.join(root, name)
                        rel = os.path.relpath(full, facts_dir).replace(os.sep, "/")
                        self.files["facts:" + rel] = full

    def tokens(self, logical):
        if logical not in self._cache:
            path = self.files.get(logical)
            if path is None or not os.path.exists(path):
                self._cache[logical] = None
            else:
                lang = T.language(logical)
                self._cache[logical] = T.tokenize(read_text(path), lang)
        return self._cache[logical]

    def literals(self, logical):
        """The set of literal texts of a whole file, or None when the file is not available.

        In a ucm file the code point `<UXXXX>` and the byte `\\xBB` are numbers as well.
        """
        src = self.tokens(logical)
        if src is None:
            return None
        lits = set()
        ucm = logical.lower().endswith(".ucm")
        for cls, text, _line in src:
            if cls == "l":
                lits.add(text)
            elif cls == "i" and ucm:
                m = UCM_WORD_RE.match(text)
                if m:
                    lits.add("n%d" % int(m.group(1) or m.group(2), 16))
        return lits


def api_names(path):
    names = set()
    if path and os.path.exists(path):
        for span in BACKTICK_RE.findall(read_text(path)):
            for w in WORD_RE.findall(span):
                names.add(w.lower())
    return names


def load_proofs(path):
    """Returns a list of (lineno, comparison, match id, path, proof)."""
    entries = []
    if not os.path.exists(path):
        return entries
    with open(path, encoding="utf-8") as fh:
        for no, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 4:
                entries.append((no, None, None, None, line))
                continue
            entries.append((no, cols[0], cols[1], cols[2], cols[3]))
    return entries


def _name_ok(text, known):
    return text in PREDECLARED or text in T.PASCAL_KEYWORDS or text in known


def _compare(toks, idents, lits):
    """Whether every identifier of the tokens is a keyword, a predeclared name or in idents, and every
    literal is in lits. Returns (holds, reason)."""
    for cls, text in toks:
        if cls == "i" and not _name_ok(text, idents):
            return False, "identifier %s does not occur" % text
        if cls == "l" and text not in lits:
            return False, "literal %s does not occur" % text
    return True, ""


def check_proof(match, proof, allowed, names):
    """Returns (holds, reason) for a proof of a match (a dict of the audit report)."""
    kind, _, rest = proof.strip().partition(" ")
    rest = rest.strip()
    toks = match["tokens"]
    if kind == "api":
        if rest:
            return False, "api takes no argument"
        for cls, text in toks:
            if cls == "l":
                return False, "literal %s" % text
            if cls == "i" and not _name_ok(text, names):
                return False, "name %s is not listed" % text
        return True, ""
    if kind == "translation":
        idents = set()
        lits = set()
        if not rest:
            return False, "no location"
        for part in rest.split(","):
            m = LOCATION_RE.match(part.strip())
            if not m:
                return False, "bad location %s" % part
            logical = m.group(1) + ":" + m.group(2)
            a, b = int(m.group(3)), int(m.group(4))
            src = allowed.tokens(logical)
            if src is None:
                return False, "no allowed file %s" % logical
            for cls, text, line in src:
                if a <= line <= b:
                    if cls in ("w", "i"):
                        idents.add(text)
                    elif cls == "l":
                        lits.add(text)
        return _compare(toks, idents, lits)
    if kind == "standard":
        lits = set()
        if not rest:
            return False, "no file"
        for part in rest.split(","):
            rel = part.strip()
            if not rel:
                return False, "empty file name"
            found = allowed.literals("facts:" + rel)
            if found is None:
                return False, "no facts file %s" % rel
            lits |= found
        return _compare(toks, set(), lits)
    return False, "unknown proof %r" % kind


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", required=True)
    ap.add_argument("--corpora", default=os.environ.get("CORPORA") or os.path.expanduser("~/.cache/tv3-corpora"))
    ap.add_argument("--repo", default=".")
    ap.add_argument("--proofs", default=None)
    ap.add_argument("--api-names", default=None)
    args = ap.parse_args(argv)
    proofs = args.proofs or os.path.join(args.repo, "tools/audit/proofs.txt")
    apidoc = args.api_names or os.path.join(args.repo, "docs/API-NAMES.md")
    allowed = Allowed(args.corpora, os.path.join(args.repo, "tools/audit/facts"))
    names = api_names(apidoc)
    with open(args.report) as fh:
        report = json.load(fh)
    by_key = {(m["comparison"], m["id"], m["path"]): m for m in report["matches"]}
    bad = 0
    for no, comp, mid, path, proof in load_proofs(proofs):
        m = by_key.get((comp, mid, path))
        if comp is None:
            ok, why = False, "malformed line"
        elif m is None:
            ok, why = False, "no such match"
        else:
            ok, why = check_proof(m, proof, allowed, names)
        print("%s:%d: %s%s" % (proofs, no, "holds" if ok else "does not hold", "" if ok else " (" + why + ")"))
        if not ok:
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
