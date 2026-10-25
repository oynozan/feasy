"""eth_call of Preflight.scenario(id) with the harness injected through a state override."""
import json
import os
import sys
import urllib.request

HARNESS = "0xFeA5000000000000000000000000000000000001"
SCENARIO_SELECTOR = "422dab0c"
# A paired scenario runs again with this bit set, the harness then skips or swaps its step under test
ALT = 1 << 128
PAIRED = {24, 25, 26, 30, 31, 32, 33, 38, 39, 40, 41, 42}

rpc, code_file = sys.argv[1], sys.argv[2]
scenario = int(sys.argv[3])
code = open(code_file).read().strip()


def post(payload, timeout):
    req = urllib.request.Request(
        rpc, json.dumps(payload).encode(), {"content-type": "application/json", "user-agent": "curl/8.9.1"}
    )
    return json.load(urllib.request.urlopen(req, timeout=timeout))


# Both runs of a pair read one block, so their views and budgets compare exactly
# Scenario 42 only means something at a block between a Thursday flip and veBTC's first write
if scenario == 42 and not os.environ.get("BLOCK"):
    print("  SKIP, set BLOCK to a block between a Thursday flip and veBTC's first write")
    sys.exit(0)

# BLOCK pins a past block, for state that only exists at one moment such as right after a flip
block = (hex(int(os.environ["BLOCK"])) if os.environ.get("BLOCK")
         else post({"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber", "params": []}, 60)["result"])


def word(b, i):
    return int.from_bytes(b[i:i + 32], "big")


def run(sid):
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [
            {
                "from": "0x000000000000000000000000000000000000dEaD",
                "to": HARNESS,
                "data": "0x" + SCENARIO_SELECTOR + sid.to_bytes(32, "big").hex(),
                "gas": hex(25_000_000),
            },
            block,
            {HARNESS: {"code": code, "balance": hex(300 * 10**18 if scenario in (15, 16, 18, 34) else 10**18)}},
        ],
    }
    resp = post(payload, 300)
    if "error" in resp:
        data = resp["error"].get("data") or "0x"
        print("REVERT", resp["error"].get("message"), data[:10])
        raw = bytes.fromhex(data[2:])
        if raw[:4].hex() == "3c1f5b33" or len(raw) > 68:
            # StepFailed(string step, bytes reason)
            body = raw[4:]
            s_off, r_off = word(body, 0), word(body, 32)
            step = body[s_off + 32:s_off + 32 + word(body, s_off)].decode()
            reason = body[r_off + 32:r_off + 32 + word(body, r_off)]
            print("step:", step)
            print("reason:", reason.hex())
            if reason[:4].hex() == "08c379a0":
                print("message:", reason[68:68 + word(reason, 36)].decode(errors="replace"))
        return None
    raw = bytes.fromhex(resp["result"][2:])

    def strings(base):
        out = []
        for k in range(word(raw, base)):
            off = base + 32 + word(raw, base + 32 + 32 * k)
            out.append(raw[off + 32:off + 32 + word(raw, off)].decode())
        return out

    vbase = word(raw, 32)
    return strings(word(raw, 0)), [word(raw, vbase + 32 + 32 * k) for k in range(word(raw, vbase))]


def show(labels, values):
    coll = 0
    ratio = 0.0
    for label, value in zip(labels, values):
        if label.startswith("==") or label.startswith("check ok") or label.startswith("CHECK FAILED"):
            print(label)
        elif label.endswith(("gas", "precompile calls", "ids")) or label == "precompile budget left":
            print(f"  {label:26} {value}")
        else:
            print(f"  {label:26} {value / 1e18:.10f}")
        if label == "trove coll":
            coll = value
        if label == "trove debt":
            ratio = coll * price / value / 1e18 if value else 0.0
            if value:
                print(f"  {'ratio':26} {ratio:.4f}")
    return ratio


def check(ok, what):
    print(f"{'check ok' if ok else 'CHECK FAILED'}: {what}")
    return ok


result = run(scenario)
if result is None:
    sys.exit(1)
labels, values = result

# Ratio from the live price, read in its own call so the scenario keeps its precompile budget
price_call = {"jsonrpc": "2.0", "id": 1, "method": "eth_call",
              "params": [{"to": "0x86bCF0841622a5dAC14A313a15f96A95421b9366", "data": "0x0fdb11cf"}, block]}
price = int(post(price_call, 60)["result"], 16)
ratio = show(labels, values)

# Final collateral ratio each scenario must land on, as (low, high)
EXPECTED = {0: (2.4995, 2.5005), 1: (2.4995, 2.5005), 2: (2.4995, 2.5005), 4: (2.4995, 2.5005),
            5: (2.7995, 2.8005), 7: (2.4995, 2.5005), 8: (2.0, 2.5005), 13: (2.4995, 2.5005), 14: (3.0, 9.9), 15: (2.4995, 2.5005), 16: (2.0, 2.5005)}
low, high = EXPECTED.get(scenario, (0.0, 99.0))
ratio_ok = low <= ratio <= high or scenario not in EXPECTED
ok = ratio_ok and not any(l.startswith("CHECK FAILED") for l in labels)

if scenario in PAIRED:
    print("== paired run, step under test skipped or swapped")
    second = run(scenario | ALT)
    if second is None:
        ok = False
    else:
        show(*second)
        ok = ok and not any(l.startswith("CHECK FAILED") for l in second[0])
        a, b = dict(zip(labels, values)), dict(zip(*second))
        for label in labels:
            if label.startswith("view ") and label in b:
                ok = check(a[label] == b[label], f"{label} {a[label]} in both runs"
                           if a[label] == b[label] else f"{label} {a[label]} vs {b[label]}") and ok
            if label.endswith(" expected precompile calls"):
                used = b["precompile budget left"] - a["precompile budget left"]
                step = label[:-len(" expected precompile calls")]
                ok = check(used == a[label], f"{step} used {used} precompile calls, expected {a[label]}") and ok

print("  PASS" if ok else "  FAIL" + ("" if ratio_ok else f" ratio {ratio:.4f} outside [{low}, {high}]"))
sys.exit(0 if ok else 1)
