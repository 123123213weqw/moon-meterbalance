"""Independent Fraction and exhaustive-assignment checks of the actual JS CLI."""

import csv
from fractions import Fraction
from hashlib import sha256
from itertools import product
import json
import os
from pathlib import Path
from random import Random
import subprocess
from tempfile import TemporaryDirectory

from uci_examples import FIXTURES, RANGES, ROOT, adapt

MOON = os.environ.get("MOON", "moon")
WH = 3_600_000_000
DIGESTS = {
    "clean-day": "3acb8a52dcb66244ff6171c95e5eb61cb612ba47f83b32a10b83500241f37257",
    "missing-minutes": "442eb85ff1b837e83e4803f0c79bcfb5db7455d003cb4be69b69ff07818815db",
}


def invoke(config, readings):
    return subprocess.run(
        [MOON, "run", "cmd/main", "--target", "js", "--", "audit", str(config), str(readings)],
        cwd=ROOT,
        capture_output=True,
        encoding="utf-8",
        check=False,
    )


def run(config, readings):
    result = invoke(config, readings)
    if result.returncode != 0:
        raise RuntimeError(f"CLI exit {result.returncode}: {result.stderr}")
    report = json.loads(result.stdout)
    assert report["schema"] == "meterbalance/report/v1"
    assert report["unit"] == "microwatt_second"
    return report


def check_uci(directory):
    """Use UCI's Wh formula and Fraction independently of the MoonBit parser."""
    columns = {
        "total": "Global_active_power",
        "kitchen": "Sub_metering_1",
        "laundry": "Sub_metering_2",
        "water_hvac": "Sub_metering_3",
    }
    for fixture, (first, last) in RANGES.items():
        source = FIXTURES / f"{fixture}.txt"
        assert sha256(source.read_bytes()).hexdigest() == DIGESTS[fixture]
        output = directory / fixture
        adapt(fixture, output)
        result = run(output / "config.json", output / "readings.csv")
        assert result["root"] == "total"
        with (
            source.open(encoding="ascii", newline="") as rows,
            (output / "source-map.csv").open(encoding="utf-8", newline="") as mapping,
        ):
            original = list(csv.DictReader(rows, delimiter=";"))
            trace = {int(row["reading_line"]): row for row in csv.DictReader(mapping)}
        assert len(result["windows"]) == last - first + 1 == len(original)
        complete, absent = 0, 0
        for index, (raw, window) in enumerate(zip(original, result["windows"], strict=True)):
            nodes = {node["meter"]: node for node in window["nodes"]}
            assert set(nodes) == set(columns)
            assert (int(window["start"]), int(window["end"])) == (index * 60, (index + 1) * 60)
            values = {}
            for meter, column in columns.items():
                node = nodes[meter]
                if raw[column] in ("?", ""):
                    assert node["own"] is None
                    continue
                measured = Fraction(raw[column])
                values[meter] = measured * 1000 / 60 if meter == "total" else measured
                evidence = node["own"]
                assert WH * values[meter] == int(evidence["amount"]), (fixture, index, meter)
                assert evidence["tolerance"] == "0"
                source_row = trace[evidence["line"]]
                assert int(source_row["original_uci_line"]) == first + index
                assert source_row["date"] == raw["Date"]
                assert source_row["time"] == raw["Time"]
                assert source_row["channel"] == column
            root = nodes["total"]
            if len(values) != 4:
                assert root["local_state"] == root["tree_state"] == "incomplete"
                assert root["nominal_residual"] is None
                assert set(root["missing"]) == set(columns) - set(values)
                absent += 1
                continue
            watts = values["total"] - sum(values[meter] for meter in columns if meter != "total")
            expected = watts * WH
            assert root["local_state"] == root["tree_state"] == "feasible", (fixture, index)
            assert expected == int(root["nominal_residual"]), (fixture, index)
            assert expected == int(root["residual_band"]["lower"]) == int(root["residual_band"]["upper"])
            complete += 1
        expected_counts = (1440, 0) if fixture == "clean-day" else (21, 15)
        assert (complete, absent) == expected_counts
        print(f"UCI {fixture}: {complete} exact residuals, {absent} incomplete minutes")


def check_nested():
    bundle = ROOT / "examples" / "nested"
    report = run(bundle / "config.json", bundle / "readings.csv")
    windows = [{node["meter"]: node for node in row["nodes"]} for row in report["windows"]]
    assert [nodes["main"]["tree_state"] for nodes in windows] == [
        "feasible", "inconsistent", "incomplete", "blocked", "inconsistent"
    ]
    assert windows[1]["main"]["local_state"] == "feasible"
    assert windows[1]["panel"]["feasible_band"] == {"lower": str(6 * WH), "upper": str(6 * WH)}
    witness = windows[1]["main"]["tree_witness"]
    assert int(witness["measured"]["upper"]) == 5 * WH
    assert int(witness["required"]["lower"]) == 6 * WH
    assert windows[2]["panel"]["missing"] == ["lighting"]
    assert windows[3]["main"]["blockers"] == ["panel"]
    witness = windows[4]["main"]["tree_witness"]
    assert int(witness["measured"]["lower"]) > int(witness["required"]["upper"])
    print("Nested example: all five states and both contradiction directions")


def check_tiny_trees(directory):
    """Enumerate complete assignments to compare root and all projected subtrees."""
    rng = Random(235)
    # Meter input order intentionally differs from the dependency order.
    names = ("device", "main", "other", "panel", "aux")
    edges = {"main": ("panel", "other"), "panel": ("device", "aux")}
    owner = {child: parent for parent, group in edges.items() for child in group}
    descendants = {
        "main": names,
        "panel": ("panel", "device", "aux"),
        "device": ("device",),
        "other": ("other",),
        "aux": ("aux",),
    }
    constraints = {"main": (1, 3), "panel": (0, 1)}
    readings, expected = [], []
    for window in range(128):
        values = {meter: (rng.randrange(9), rng.randrange(3)) for meter in names}
        domains = {meter: range(max(0, midpoint - radius), midpoint + radius + 1)
                   for meter, (midpoint, radius) in values.items()}
        start = 60 * window
        for meter in names:
            value, tolerance = values[meter]
            readings.append([meter, start, start + 60, value, "Wh", tolerance])
        projections = {}
        for meter, group in descendants.items():
            possible = set()
            for trial in product(*(domains[node] for node in group)):
                actual = dict(zip(group, trial, strict=True))
                if all(
                    lo <= actual[parent] - sum(actual[child] for child in edges[parent]) <= hi
                    for parent, (lo, hi) in constraints.items() if parent in actual
                ):
                    possible.add(actual[meter])
            projections[meter] = (min(possible), max(possible)) if possible else None
        expected.append(projections)
    config = directory / "tiny.json"
    config.write_text(json.dumps({
        "schema": "meterbalance/v1",
        "window": {"start": "0", "step": 60, "count": len(expected)},
        "meters": [
            {"id": meter, "parent": owner.get(meter), **(
                {"residual_min_uws": str(WH * constraints[meter][0]),
                 "residual_max_uws": str(WH * constraints[meter][1])}
                if meter in constraints else {}
            )}
            for meter in names
        ],
    }), encoding="utf-8")
    data = directory / "tiny.csv"
    with data.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("meter", "start", "end", "value", "unit", "tolerance"))
        writer.writerows(readings)
    report = run(config, data)
    for index, (result, expected_window) in enumerate(zip(report["windows"], expected, strict=True)):
        for node in result["nodes"]:
            wanted = expected_window[node["meter"]]
            band = node["feasible_band"]
            if wanted is None:
                assert node["tree_state"] in {"inconsistent", "blocked"}, (index, node)
                assert band is None
            else:
                assert node["tree_state"] in {"feasible", "leaf"}, (index, node)
                assert (int(band["lower"]), int(band["upper"])) == tuple(WH * v for v in wanted), (index, node)
    print(f"Exhaustive independent oracle: {len(expected) * len(names)} subtree projections")
    with data.open("a", encoding="utf-8", newline="") as stream:
        csv.writer(stream).writerow(readings[0])
    error = invoke(config, data)
    assert error.returncode != 0
    assert not error.stdout
    assert "duplicates reading at line 2" in error.stderr
    print("CLI input error: duplicate rejected with both row references")


if __name__ == "__main__":
    build = ROOT / "_build"
    build.mkdir(exist_ok=True)
    with TemporaryDirectory(dir=build) as temporary:
        work = Path(temporary)
        check_nested()
        check_tiny_trees(work)
        check_uci(work)

