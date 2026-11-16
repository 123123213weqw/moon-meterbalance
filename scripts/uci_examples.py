"""Adapt two fixed, attributed UCI excerpts into MeterBalance inputs."""

import argparse
import csv
from datetime import datetime
import io
import itertools
import json
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "examples" / "uci"
RANGES = {"clean-day": (398, 1837), "missing-minutes": (190478, 190513)}
CHANNELS = (
    ("total", "Global_active_power", "mean_kW"),
    ("kitchen", "Sub_metering_1", "Wh"),
    ("laundry", "Sub_metering_2", "Wh"),
    ("water_hvac", "Sub_metering_3", "Wh"),
)


def adapt(name, destination):
    """Write a configured interval grid, measurements, and original row map."""
    first, last = RANGES[name]
    with (FIXTURES / f"{name}.txt").open(encoding="ascii", newline="") as stream:
        source = list(csv.DictReader(stream, delimiter=";"))
    if len(source) != last - first + 1:
        raise ValueError(f"unexpected original line count for {name}")
    destination.mkdir(parents=True, exist_ok=True)
    config = {
        "schema": "meterbalance/v1",
        "window": {"start": "0", "step": 60, "count": len(source)},
        "meters": [
            {"id": meter, "parent": "total" if index else None}
            for index, (meter, _, _) in enumerate(CHANNELS)
        ],
    }
    (destination / "config.json").write_text(
        json.dumps(config, indent=2) + "\n", encoding="utf-8"
    )
    origin = None
    with (
        (destination / "readings.csv").open("w", encoding="utf-8", newline="") as readings,
        (destination / "source-map.csv").open("w", encoding="utf-8", newline="") as mapping,
    ):
        writer = csv.writer(readings, lineterminator="\n")
        trace = csv.writer(mapping, lineterminator="\n")
        writer.writerow(("meter", "start", "end", "value", "unit", "tolerance"))
        trace.writerow(("reading_line", "original_uci_line", "date", "time", "channel"))
        line = 1
        for index, row in enumerate(source):
            date, time = row["Date"], row["Time"]
            stamp = datetime.strptime(f"{date} {time}", "%d/%m/%Y %H:%M:%S")
            if origin is None:
                origin = stamp
            start = index * 60
            if (stamp - origin).total_seconds() != start:
                raise ValueError(f"{name} is not a contiguous one-minute sample at row {first + index}")
            for meter, channel, unit in CHANNELS:
                value = row[channel]
                if value in ("?", ""):
                    continue
                line += 1
                writer.writerow((meter, start, start + 60, value, unit, "0"))
                trace.writerow((line, first + index, date, time, channel))


def verify_archive(path):
    """Compare all selected text rows against an original complete UCI ZIP."""
    with ZipFile(path) as archive:
        for name, (first, last) in RANGES.items():
            with archive.open("household_power_consumption.txt") as packed:
                stream = io.TextIOWrapper(packed, encoding="ascii", newline=None)
                header = next(stream)
                lines = itertools.islice(stream, first - 2, last - 1)
                excerpt = header + "".join(lines)
            expected = (FIXTURES / f"{name}.txt").read_text(encoding="ascii")
            if excerpt != expected:
                raise ValueError(f"source mismatch in {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--archive", type=Path, help="optionally compare the fixture bytes to a downloaded UCI ZIP")
    args = parser.parse_args()
    if args.archive:
        verify_archive(args.archive)
    for fixture in RANGES:
        adapt(fixture, args.output / fixture)

