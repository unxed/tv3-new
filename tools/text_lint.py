#!/usr/bin/env python3
"""Text rules of the repository (CLAUDE.md, rule 4).

Checks:
  * every tracked file is UTF-8, has no byte order mark and no U+FFFD;
  * no Cyrillic outside tests/;
  * the file names and the text keep to the neutral rule (a list of patterns);
  * optionally the messages of the commits of a range and given texts; in a commit message the trailer
    lines that begin with "Assisted-by:" are not checked, every other line is.

Usage:
  text_lint.py [--repo DIR] [--commits RANGE] [--text FILE]... [--json FILE]

Exit code 0 when nothing is found, 1 otherwise.
"""
import argparse
import json
import re
import subprocess
import sys

SELF = "tools/text_lint.py"
# The report written by the verdict job. It quotes the findings of the checks, including the words the
# rule forbids, so its text is not judged by the rule; its encoding is.
REPORT = "VERDICT.md"

# The neutral rule. Non-ASCII parts are written with escape sequences.
NEUTRAL_PATTERNS = [
    ("tool name", r"lunobot"),
    ("tool name", "\u043b\u0443\u043d\u043e\u0431\u043e\u0442"),
    ("tool name", r"\bclaude\b(?!\.md)"),
    ("tool name", r"\b(?:sonnet|opus|codex)\b"),
    ("process word", r"\bagents?\b"),
    ("process word", "\u0430\u0433\u0435\u043d\u0442\\w*"),
    ("decision wording", r"\bowner decided\b"),
    ("decision wording", "\u0432\u043b\u0430\u0434\u0435\u043b\\w*"),
    ("decision wording", "\u0445\u043e\u0437\u044f\u0438\\w*"),
    ("process word", r"\brewrit\w*"),
    ("process word", "\u043f\u0435\u0440\u0435\u043f\u0438\u0441\u0430\\w*"),
    ("process word", r"\bchat\b"),
]
NEUTRAL_RE = [(label, re.compile(p, re.IGNORECASE)) for label, p in NEUTRAL_PATTERNS]
CYRILLIC_RE = re.compile("[\u0400-\u04ff]")


def neutral_findings(text):
    """Returns (label, matched text) for every neutral-rule hit in text."""
    found = []
    for label, rx in NEUTRAL_RE:
        for m in rx.finditer(text):
            found.append((label, m.group(0)))
    return found


def check_text(where, text, allow_cyrillic=False):
    """Findings for a text that is already decoded."""
    out = []
    if "\ufeff" in text[:1]:
        out.append({"where": where, "rule": "byte order mark", "detail": ""})
    if "\ufffd" in text:
        out.append({"where": where, "rule": "replacement character", "detail": ""})
    if not allow_cyrillic and CYRILLIC_RE.search(text):
        out.append({"where": where, "rule": "cyrillic", "detail": ""})
    for label, hit in neutral_findings(text):
        out.append({"where": where, "rule": "neutral: " + label, "detail": hit})
    return out


def check_name(path):
    out = []
    for label, hit in neutral_findings(path):
        out.append({"where": path, "rule": "neutral file name: " + label, "detail": hit})
    if CYRILLIC_RE.search(path) and not path.startswith("tests/"):
        out.append({"where": path, "rule": "cyrillic in file name", "detail": ""})
    return out


def check_bytes(path, data):
    """Findings for the content of a tracked file."""
    if data.startswith(b"\xef\xbb\xbf"):
        return [{"where": path, "rule": "byte order mark", "detail": ""}]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return [{"where": path, "rule": "not UTF-8", "detail": ""}]
    if path in (SELF, REPORT):
        # the script is exempt from the check of its own text, the report from the check of the words it quotes
        if "\ufffd" in text:
            return [{"where": path, "rule": "replacement character", "detail": ""}]
        return []
    # the documents of standards of the facts are kept as published
    return check_text(path, text, allow_cyrillic=path.startswith(("tests/", "tools/audit/facts/")))


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True,
                          stdout=subprocess.PIPE).stdout


def tracked_files(repo):
    raw = git(repo, "ls-files", "-z")
    return [p.decode("utf-8", "surrogateescape") for p in raw.split(b"\0") if p]


def commit_messages(repo, rng):
    raw = git(repo, "log", "--format=%H%x00%B%x01", rng).decode("utf-8", "replace")
    result = []
    for chunk in raw.split("\x01"):
        chunk = chunk.lstrip("\n")
        if not chunk.strip():
            continue
        sha, _, body = chunk.partition("\x00")
        body = "\n".join(line for line in body.split("\n") if not line.startswith("Assisted-by:"))
        result.append((sha, body))
    return result


def run(repo, commits=None, texts=None):
    findings = []
    files = tracked_files(repo)
    for path in files:
        findings.extend(check_name(path))
        try:
            with open(repo.rstrip("/") + "/" + path, "rb") as fh:
                data = fh.read()
        except OSError:
            continue
        findings.extend(check_bytes(path, data))
    ncommits = 0
    if commits:
        for sha, body in commit_messages(repo, commits):
            ncommits += 1
            findings.extend(check_text("commit " + sha[:12], body))
    for label, text in (texts or []):
        findings.extend(check_text(label, text))
    try:
        head = git(repo, "rev-parse", "HEAD").decode().strip()
    except subprocess.CalledProcessError:
        head = None
    return {"head": head, "files": len(files), "commits": ncommits,
            "findings": findings, "pass": not findings}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", default=".")
    ap.add_argument("--commits", help="git revision range whose messages are checked")
    ap.add_argument("--text", action="append", default=[],
                    help="file with a text to check (the title or description of a pull request)")
    ap.add_argument("--json", help="write the report here")
    args = ap.parse_args(argv)
    texts = []
    for name in args.text:
        with open(name, "rb") as fh:
            data = fh.read()
        texts.append(("text " + name, data.decode("utf-8", "replace")))
    report = run(args.repo, args.commits, texts)
    if args.json:
        with open(args.json, "w") as fh:
            json.dump(report, fh, indent=1)
    for f in report["findings"]:
        print("TEXT: %s: %s %s" % (f["where"], f["rule"], f["detail"]))
    print("TEXT PASS" if report["pass"] else "TEXT FAIL")
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
