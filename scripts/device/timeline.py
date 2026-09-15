#!/usr/bin/env python3
"""Prints Mindlore diagnostics as a compact timeline, one line per event, grouped by app session.

Usage: timeline.py <log file or directory> [--sessions N] [--since ISO-TIME]
"""

import argparse
import json
import pathlib
import re
import sys

NOISY_KEYS = {"t", "session", "event"}
UUID = re.compile(r"\b([0-9A-Fa-f]{8})-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b")


def load(path: pathlib.Path):
    files = sorted(path.glob("diagnostics*.jsonl"), key=lambda p: p.name != "diagnostics.1.jsonl") if path.is_dir() else [path]
    events = []
    for file in files:
        for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), start=1):
            if not line.strip():
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                events.append({"t": "?", "session": "?", "event": "UNPARSEABLE", "file": file.name, "line": number})
    return events


def format_value(value):
    if isinstance(value, float):
        return f"{value:.2f}"
    if isinstance(value, str):
        return UUID.sub(r"\1", value)
    return str(value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--sessions", type=int, default=5, help="show only the most recent N sessions")
    parser.add_argument("--since", help="show only events at or after this ISO timestamp")
    args = parser.parse_args([a for a in sys.argv[1:] if a])

    path = pathlib.Path(args.path)
    if not path.exists():
        print(f"no diagnostics at {path}")
        return
    events = load(path)
    if args.since:
        events = [e for e in events if e.get("t", "") >= args.since]

    order = []
    for event in events:
        if event.get("session") not in order:
            order.append(event.get("session"))
    keep = set(order[-args.sessions:])

    current = None
    for event in events:
        session = event.get("session")
        if session not in keep:
            continue
        if session != current:
            current = session
            print(f"\n== session {session}")
        time = event.get("t", "?")
        clock = time[11:23] if len(time) >= 23 else time
        details = " ".join(f"{k}={format_value(v)}" for k, v in sorted(event.items()) if k not in NOISY_KEYS)
        flag = "!! " if any(word in event.get("event", "") for word in ("failed", "Failed", "denied", "Denied", "UNPARSEABLE")) else "   "
        print(f"{flag}{clock} {event.get('event')} {details}".rstrip())


if __name__ == "__main__":
    main()
