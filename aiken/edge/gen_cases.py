#!/usr/bin/env python3
"""Generate cases.csv for the edge-case benchmark scripts.

Each script gets DATA_DIR/Edge<Name>/cases.csv in the cross-bench format
(name,kind,expected,args). Expected results come from the Python reference
implementations below; args are the hex CBOR encodings of the Data arguments,
separated by ';'. Randomness is seeded, so the output is deterministic.
"""

import os
import random
import sys

DATA_DIR = sys.argv[1] if len(sys.argv) > 1 else "/Users/sho/fun/cross-bench-data"

# ---------------------------------------------------------------------------
# Plutus Data and its CBOR encoding
# ---------------------------------------------------------------------------


class Constr:
    def __init__(self, tag, fields):
        self.tag = tag
        self.fields = list(fields)


class Map:
    def __init__(self, entries):
        self.entries = list(entries)


def head(major, n):
    if n < 24:
        return bytes([major << 5 | n])
    for extra, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
        if n < 1 << (8 * size):
            return bytes([major << 5 | extra]) + n.to_bytes(size, "big")
    raise ValueError("argument too large")


def encode_bytes(b):
    if len(b) <= 64:
        return head(2, len(b)) + b
    chunks = b"".join(head(2, len(b[i:i + 64])) + b[i:i + 64] for i in range(0, len(b), 64))
    return bytes([0x5F]) + chunks + bytes([0xFF])


def encode_int(n):
    if 0 <= n < 1 << 64:
        return head(0, n)
    if -(1 << 64) <= n < 0:
        return head(1, -1 - n)
    if n >= 0:
        return head(6, 2) + encode_bytes(n.to_bytes((n.bit_length() + 7) // 8, "big"))
    m = -1 - n
    return head(6, 3) + encode_bytes(m.to_bytes((m.bit_length() + 7) // 8, "big"))


def encode(d):
    if isinstance(d, bool):
        raise TypeError("use Constr for booleans")
    if isinstance(d, int):
        return encode_int(d)
    if isinstance(d, bytes):
        return encode_bytes(d)
    if isinstance(d, list):
        return head(4, len(d)) + b"".join(encode(x) for x in d)
    if isinstance(d, Map):
        return head(5, len(d.entries)) + b"".join(encode(k) + encode(v) for k, v in d.entries)
    if isinstance(d, Constr):
        body = head(4, len(d.fields)) + b"".join(encode(x) for x in d.fields)
        if 0 <= d.tag < 7:
            return head(6, 121 + d.tag) + body
        if 7 <= d.tag < 128:
            return head(6, 1280 + d.tag - 7) + body
        return head(6, 102) + head(4, 2) + encode_int(d.tag) + body
    raise TypeError(repr(d))


FAIL = "FAIL"
rng = random.Random(20261107)


def ints(n, lo=-1000, hi=1000):
    return [rng.randint(lo, hi) for _ in range(n)]


def blob(n):
    return bytes(rng.getrandbits(8) for _ in range(n))


# ---------------------------------------------------------------------------
# Reference implementations and cases
# ---------------------------------------------------------------------------


def list_sum(xs):
    return sum(xs)


def map_filter_count(xs, threshold):
    return sum(1 for x in xs if 2 * x + 1 > threshold)


def wide_record(fields):
    return fields[0] + fields[6] + fields[11]


def value_lookup(value, policy, token):
    for p, tokens in value:
        if p == policy:
            for t, q in tokens:
                if t == token:
                    return q
            return 0
    return 0


def enum_dispatch(tag, fields):
    a = fields
    if tag == 0:
        return a[0] + a[1]
    if tag == 1:
        return a[0] - a[1]
    if tag == 2:
        return a[0] * a[1]
    if tag == 3:
        return -a[0]
    if tag == 4:
        return a[0] * a[1] + a[2]
    if tag == 5:
        return a[0] // a[1]
    if tag == 6:
        return a[0] % a[1]
    if tag == 7:
        return min(max(a[0], a[1]), a[2])
    raise ValueError(tag)


def guard_order(xs, flag):
    s = sum(xs)
    return s if flag == 1 else FAIL


def byte_search(xs, target):
    for i, x in enumerate(xs):
        if x == target:
            return i
    return -1


def nested_lists(xss):
    return sum(len(xs) for xs in xss if xs and xs[0] % 2 == 0)


def horner(coefficients, x):
    acc = 0
    for c in coefficients:
        acc = acc * x + c
    return acc


def all_any(items, target):
    return 1 if all(a < b for a, b, _ in items) and any(c == target for _, _, c in items) else 0


def scripts():
    out = {}

    # 1. ListSum
    cases = []
    for name, xs in [("empty", []), ("one", [7]), ("ten", ints(10)), ("fifty", ints(50)),
                     ("hundred", ints(100)), ("two hundred", ints(200)),
                     ("big numbers", [rng.randint(-10**30, 10**30) for _ in range(20)])]:
        cases.append((name, "bench", list_sum(xs), [xs]))
    out["ListSum"] = cases

    # 2. MapFilterCount
    cases = []
    for name, xs, t in [("empty", [], 0), ("one kept", [5], 3), ("one dropped", [1], 10),
                        ("ten", ints(10), 0), ("hundred", ints(100), 100),
                        ("two hundred all kept", ints(200, 0, 1000), -1),
                        ("two hundred none kept", ints(200, -1000, 0), 5000)]:
        cases.append((name, "bench", map_filter_count(xs, t), [xs, t]))
    out["MapFilterCount"] = cases

    # 3. WideRecord
    cases = []
    for name, fs in [("zeros", [0] * 12), ("small", list(range(1, 13))), ("random", ints(12)),
                     ("negative", ints(12, -10**6, -1)), ("big", [rng.randint(-10**40, 10**40) for _ in range(12)]),
                     ("mixed", ints(12, -50, 50))]:
        cases.append((name, "bench", wide_record(fs), [Constr(0, fs)]))
    out["WideRecord"] = cases

    # 4. ValueLookup
    def make_value(n_policies, n_tokens):
        value = []
        for i in range(n_policies):
            policy = blob(28)
            tokens = [(blob(rng.randint(4, 32)), rng.randint(1, 10**9)) for _ in range(n_tokens)]
            value.append((policy, tokens))
        return value

    def value_data(value):
        return Map([(p, Map(list(ts))) for p, ts in value])

    cases = []
    v = make_value(1, 1)
    cases.append(("ada only, hit", "bench", value_lookup(v, v[0][0], v[0][1][0][0]), [value_data(v), v[0][0], v[0][1][0][0]]))
    v = make_value(8, 4)
    for name, (pi, ti) in [("first", (0, 0)), ("middle", (4, 2)), ("last", (7, 3))]:
        p, t = v[pi][0], v[pi][1][ti][0]
        cases.append((name + " of 8x4", "bench", value_lookup(v, p, t), [value_data(v), p, t]))
    cases.append(("absent policy of 8x4", "bench", 0, [value_data(v), blob(28), v[0][1][0][0]]))
    cases.append(("absent token of 8x4", "bench", 0, [value_data(v), v[5][0], blob(10)]))
    w = make_value(30, 3)
    p, t = w[29][0], w[29][1][2][0]
    cases.append(("last of 30x3", "bench", value_lookup(w, p, t), [value_data(w), p, t]))
    cases.append(("empty value", "bench", 0, [Map([]), blob(28), blob(8)]))
    out["ValueLookup"] = cases

    # 5. EnumDispatch
    arity = [2, 2, 2, 1, 3, 2, 2, 3]
    cases = []
    for tag in range(8):
        a = ints(arity[tag], -10**6, 10**6)
        if tag in (5, 6) and a[1] == 0:
            a[1] = 7
        if tag == 7:
            a[1], a[2] = sorted((a[1], a[2]))
        cases.append((f"tag {tag}", "bench", enum_dispatch(tag, a), [Constr(tag, a)]))
    cases.append(("tag 7 below range", "test", enum_dispatch(7, [-5, 0, 10]), [Constr(7, [-5, 0, 10])]))
    cases.append(("tag 6 negative", "test", enum_dispatch(6, [-17, 5]), [Constr(6, [-17, 5])]))
    out["EnumDispatch"] = cases

    # 6. GuardOrder
    cases = []
    for name, xs, flag in [("accept empty", [], 1), ("accept ten", ints(10), 1),
                           ("accept hundred", ints(100), 1), ("accept two hundred", ints(200), 1),
                           ("reject empty (reject)", [], 0), ("reject ten (reject)", ints(10), 2),
                           ("reject hundred (reject)", ints(100), 0),
                           ("reject two hundred (reject)", ints(200), -1)]:
        cases.append((name, "bench", guard_order(xs, flag), [xs, flag]))
    out["GuardOrder"] = cases

    # 7. ByteSearch
    cases = []
    pool = [blob(32) for _ in range(200)]
    for name, xs, target in [("empty", [], blob(32)), ("one hit", pool[:1], pool[0]),
                             ("ten, at 0", pool[:10], pool[0]), ("ten, at 9", pool[:10], pool[9]),
                             ("hundred, at 50", pool[:100], pool[50]),
                             ("two hundred, absent", pool, blob(32)),
                             ("two hundred, at 199", pool, pool[199]),
                             ("short keys", [blob(1) + bytes([i]) for i in range(20)], None)]:
        if target is None:
            target = xs[13]
        cases.append((name, "bench", byte_search(xs, target), [xs, target]))
    cases.append(("duplicates, first wins", "test", byte_search([pool[3], pool[5], pool[5]], pool[5]),
                  [[pool[3], pool[5], pool[5]], pool[5]]))
    out["ByteSearch"] = cases

    # 8. NestedLists
    def inner_lists(n, max_len):
        return [ints(rng.randint(0, max_len), 0, 100) for _ in range(n)]

    cases = []
    for name, xss in [("empty", []), ("one empty", [[]]), ("one even", [[2, 3, 5]]),
                      ("ten", inner_lists(10, 6)), ("fifty", inner_lists(50, 6)),
                      ("hundred", inner_lists(100, 4)), ("ten long", inner_lists(10, 40))]:
        cases.append((name, "bench", nested_lists(xss), [xss]))
    out["NestedLists"] = cases

    # 9. Horner
    cases = []
    for name, cs, x in [("empty", [], 5), ("constant", [42], 3), ("degree 3", [1, -2, 0, 7], 4),
                        ("degree 10", ints(11, -9, 9), 2), ("degree 50", ints(51, -9, 9), 3),
                        ("degree 100 at -1", ints(101, -9, 9), -1), ("degree 100 at 7", ints(101, -9, 9), 7)]:
        cases.append((name, "bench", horner(cs, x), [cs, x]))
    out["Horner"] = cases

    # 10. AllAny
    def items(n, target, hit_at=None, bad_at=None):
        out = []
        for i in range(n):
            a = rng.randint(-100, 100)
            b = a + rng.randint(1, 50)
            if bad_at is not None and i == bad_at:
                b = a
            c = target if hit_at is not None and i == hit_at else blob(16)
            out.append((a, b, c))
        return out

    def items_data(xs):
        return [Constr(0, [a, b, c]) for a, b, c in xs]

    target = blob(16)
    cases = []
    for name, xs in [("empty", []), ("one hit", items(1, target, 0)), ("ten, hit last", items(10, target, 9)),
                     ("ten, no hit", items(10, target)), ("hundred, hit first", items(100, target, 0)),
                     ("hundred, bad at 3", items(100, target, 50, 3)),
                     ("hundred, bad at 99", items(100, target, 0, 99)),
                     ("two hundred, hit last", items(200, target, 199))]:
        cases.append((name, "bench", all_any(xs, target), [items_data(xs), target]))
    out["AllAny"] = cases

    return out


def quote(field):
    if any(c in field for c in ',"\r\n'):
        return '"' + field.replace('"', '""') + '"'
    return field


def main():
    for name, cases in scripts().items():
        vdir = os.path.join(DATA_DIR, "Edge" + name)
        os.makedirs(vdir, exist_ok=True)
        lines = ["name,kind,expected,args"]
        seen = set()
        for case_name, kind, expected, args in cases:
            assert (kind, case_name) not in seen, case_name
            seen.add((kind, case_name))
            fields = [case_name, kind, str(expected), ";".join(encode(a).hex() for a in args)]
            lines.append(",".join(quote(f) for f in fields))
        with open(os.path.join(vdir, "cases.csv"), "w") as f:
            f.write("\n".join(lines) + "\n")
        print(f"Edge{name}: {len(cases)} cases")


if __name__ == "__main__":
    main()
