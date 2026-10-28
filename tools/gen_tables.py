# Generator of src/tvcp.inc and src/tvcsets.inc: the single-byte code page tables.
"""Prints one of the two Pascal include files on the standard output.

The mapping files are in tools/audit/facts/charsets/:
  CPnnn.TXT, KOI8-R.TXT, KOI8-U.TXT, ROMAN.TXT, 8859-n.TXT   lines "0xBB<TAB>0xUUUU<TAB>#NAME"; a line
                                                           without the second column is an undefined byte;
  ibm-720, ibm-858 and ibm-1125 (.ucm)                      lines "<UXXXX> \\xBB |0"; only the roundtrip
                                                           lines (|0) of one-byte sequences are taken.

cp    src/tvcp.inc: Cp437 ... Cp1125, array[0..255] of Word, the Unicode value that the page shows for
      each byte, 0 for an undefined byte of 80h or more. The entries 20h..7Eh are ASCII, the entries 0..1Fh and 7Fh
      are the glyphs of the original PC display, the entries 80h..FFh follow the mapping file.
sets  src/tvcsets.inc: Set437 ... Set10000, array[0..255] of Word, the Unicode value of the byte, 0
      for an undefined byte of 80h or more; the entries 0..127 are the identity, the entries 128..255
      follow the mapping file.

The program stops with a message and exit code 1 when a mapping file is missing or a line cannot be parsed.

Usage: gen_tables.py cp > src/tvcp.inc
       gen_tables.py sets > src/tvcsets.inc
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FACTS = os.path.join(HERE, "audit", "facts", "charsets")

UNDEFINED_CP = 0
UNDEFINED_SET = 0

UNDEFINED_NOTE = "a value 0 at a byte of 80h or more means that the byte is undefined"

DOS_LOW = (437, 737, 775)
DOS_MID = (850, 852, 855, 857, 858)
DOS_RUSSIAN_RANGE = range(860, 867)
DOS_LAST = (869,)
DOS_CYRILLIC = (1125,)
WINDOWS_RANGE = range(1250, 1259)
ISO_PARTS = [part for part in range(1, 17) if part != 12]

CP_IDS = (list(DOS_LOW) + list(DOS_MID) + list(DOS_RUSSIAN_RANGE) + list(DOS_LAST)
          + list(DOS_CYRILLIC))

SET_IDS = ([437, 720, 737, 775] + list(DOS_MID[:]) + list(DOS_RUSSIAN_RANGE) + [869, 874]
           + list(DOS_CYRILLIC) + list(WINDOWS_RANGE)
           + [20866, 21866]
           + [28590 + n for n in ISO_PARTS]
           + [10000])

UCM_FILES = {
    720: "ibm-720_P100-1997.ucm",
    858: "ibm-858_P100-1997.ucm",
    1125: "ibm-1125_P100-1997.ucm",
}

# The glyphs of the bytes 0..1Fh of the original display.
GLYPHS = [0x0000, 0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
          0x25D8, 0x25CB, 0x25D9, 0x2642, 0x2640, 0x266A, 0x266B, 0x263C,
          0x25BA, 0x25C4, 0x2195, 0x203C, 0x00B6, 0x00A7, 0x25AC, 0x21A8,
          0x2191, 0x2193, 0x2192, 0x2190, 0x221F, 0x2194, 0x25B2, 0x25BC]
GLYPH_7F = 0x2302


class TableError(Exception):
    """A mapping file is missing or has a line that cannot be parsed."""


TXT_RE = re.compile(r"^(0x[0-9A-Fa-f]{2})(?:\s+(0x[0-9A-Fa-f]{4}))?$")
UCM_RE = re.compile(r"^<U([0-9A-Fa-f]{4,6})>\s+((?:\\x[0-9A-Fa-f]{2})+)\s+\|([0-9])$")


def parse_txt_line(line):
    """Parses a line of a text mapping file.

    Returns None for a blank or comment line, (byte, value) for a mapped byte and (byte, None) for an
    undefined byte. Raises ValueError for any other line.
    """
    text = line.replace("\x1a", "").split("#", 1)[0].strip()
    if not text:
        return None
    m = TXT_RE.match(text)
    if m is None:
        raise ValueError("cannot parse the line %r" % line)
    value = m.group(2)
    return (int(m.group(1), 16), None if value is None else int(value, 16))


def parse_ucm_line(line):
    """Parses a line of the CHARMAP section of a ucm file.

    Returns (byte, value) for a roundtrip line (|0) of a one-byte sequence and None for a blank or comment
    line, for a fallback line and for a sequence of more than one byte. Raises ValueError for any other
    line.
    """
    text = line.split("#", 1)[0].strip()
    if not text:
        return None
    m = UCM_RE.match(text)
    if m is None:
        raise ValueError("cannot parse the line %r" % line)
    if m.group(3) != "0":
        return None
    sequence = m.group(2)
    if len(sequence) != 4:
        return None
    value = int(m.group(1), 16)
    if value > 0xFFFF:
        raise ValueError("the code point is out of the range: %r" % line)
    return (int(sequence[2:], 16), value)


def add_entry(result, byte, value, where):
    if value is None:
        return
    if byte in result and result[byte] != value:
        raise TableError("%s: the byte 0x%02X is mapped twice" % (where, byte))
    result[byte] = value


def read_txt(path, lines):
    result = {}
    for number, line in enumerate(lines, 1):
        where = "%s:%d" % (path, number)
        try:
            parsed = parse_txt_line(line)
        except ValueError as e:
            raise TableError("%s: %s" % (where, e))
        if parsed is not None:
            add_entry(result, parsed[0], parsed[1], where)
    return result


def read_ucm(path, lines):
    result = {}
    in_map = False
    seen_map = False
    for number, line in enumerate(lines, 1):
        where = "%s:%d" % (path, number)
        word = line.strip()
        if not in_map:
            if word == "CHARMAP":
                in_map = True
                seen_map = True
            continue
        if word == "END CHARMAP":
            in_map = False
            continue
        try:
            parsed = parse_ucm_line(line)
        except ValueError as e:
            raise TableError("%s: %s" % (where, e))
        if parsed is not None:
            add_entry(result, parsed[0], parsed[1], where)
    if not seen_map:
        raise TableError("%s: no CHARMAP section" % path)
    return result


def source_name(ident):
    """The name of the mapping file of a page or set."""
    if ident in UCM_FILES:
        return UCM_FILES[ident]
    if ident == 20866:
        return "KOI8-R.TXT"
    if ident == 21866:
        return "KOI8-U.TXT"
    if ident == 10000:
        return "ROMAN.TXT"
    if 28591 <= ident <= 28606:
        return "8859-%d.TXT" % (ident - 28590)
    return "CP%d.TXT" % ident


def read_mapping(root, ident):
    """The dictionary byte -> Unicode value of the defined bytes of the mapping file of ident."""
    name = source_name(ident)
    path = os.path.join(root, name)
    if not os.path.isfile(path):
        raise TableError("the mapping file is missing: %s" % path)
    try:
        with open(path, "rb") as fh:
            lines = fh.read().decode("latin-1").split("\n")
    except OSError as e:
        raise TableError("%s: %s" % (path, e))
    if name.endswith(".ucm"):
        return read_ucm(path, lines)
    return read_txt(path, lines)


def cp_table(mapping):
    """The table of a page for the dictionary of its mapping file."""
    table = [UNDEFINED_CP] * 256
    for byte in range(0x20, 0x7F):
        table[byte] = byte
    for byte in range(32):
        table[byte] = GLYPHS[byte]
    table[0x7F] = GLYPH_7F
    for byte in range(0x80, 0x100):
        table[byte] = mapping.get(byte, UNDEFINED_CP)
    return table


def set_table(mapping):
    """The table of a set for the dictionary of its mapping file."""
    table = list(range(128)) + [UNDEFINED_SET] * 128
    for byte in range(0x80, 0x100):
        table[byte] = mapping.get(byte, UNDEFINED_SET)
    return table


def cp_tables(root=FACTS):
    """The list (table name, mapping file name, values) of the pages, in order."""
    return [("Cp%d" % ident, source_name(ident), cp_table(read_mapping(root, ident)))
            for ident in CP_IDS]


def set_tables(root=FACTS):
    """The list (table name, mapping file name, values) of the sets, in order."""
    return [("Set%d" % ident, source_name(ident), set_table(read_mapping(root, ident)))
            for ident in SET_IDS]


def format_table(name, values):
    lines = ["  %s: array[0..255] of Word = (" % name]
    for row in range(16):
        items = ["$%04X" % v for v in values[row * 16:row * 16 + 16]]
        lines.append("    " + ", ".join(items) + ("," if row < 15 else ""))
    lines.append("  );")
    return lines


def render(kind, root=FACTS):
    """The text of the include file: kind is "cp" or "sets"."""
    if kind == "cp":
        tables = cp_tables(root)
        title = "Code pages: the Unicode value of each byte"
    elif kind == "sets":
        tables = set_tables(root)
        title = "Single-byte sets: the Unicode value of each byte"
    else:
        raise TableError("unknown kind %r, expected cp or sets" % kind)
    out = ["{ Generated by tools/gen_tables.py }", "{ %s }" % title, "{ %s }" % UNDEFINED_NOTE]
    for name, source, _ in tables:
        out.append("{ %s: %s }" % (name, source))
    out.append("")
    out.append("const")
    for n, (name, _, values) in enumerate(tables):
        if n:
            out.append("")
        out += format_table(name, values)
    return "\n".join(out) + "\n"


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1 or args[0] not in ("cp", "sets"):
        sys.stderr.write("usage: gen_tables.py cp|sets\n")
        return 2
    try:
        text = render(args[0])
    except TableError as e:
        sys.stderr.write("gen_tables.py: %s\n" % e)
        return 1
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
