#!/usr/bin/python3
"""Writes regenerated insights into the story seed's chapter files.

Reads the JSON lines StorySeedRegeneration wrote (one story entry per line, keyed by its date)
and replaces every AI-derived field of the matching entry in Mindlore/Debug/DemoStory+Chapter*.swift.
The date, title, and text are never touched. Prints a summary to review, never entry text.

    merge-story-insights.py <story-insights.jsonl>   merge, then report
    merge-story-insights.py --roundtrip               rewrite unchanged; the files must not change
"""
import collections
import glob
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CHAPTERS = sorted(glob.glob(os.path.join(ROOT, "Mindlore", "Debug", "DemoStory+Chapter*.swift")))
OPEN, CLOSE = '#"""\n', '\n"""#'
# The seed's own key order; derived fields in between, absent ones left out.
ORDER = ["date", "title", "text", "summary", "mood", "secondaryMood", "kind", "areas", "tags",
         "mentions", "sections", "opens", "resolves", "touches"]
KEPT = {"date", "title", "text"}


def split(source):
    start = source.index(OPEN) + len(OPEN)
    end = source.index(CLOSE, start)
    return source[:start], source[start:end], source[end:]


def ordered(entry):
    unknown = set(entry) - set(ORDER)
    if unknown:
        sys.exit(f"unknown keys {sorted(unknown)} in {entry['date']}")
    return {key: entry[key] for key in ORDER if key in entry}


def render(entries):
    text = json.dumps([ordered(e) for e in entries], indent=2, ensure_ascii=False)
    if '"""#' in text:
        sys.exit('refusing to write: a value contains """#, which would end the Swift raw string')
    return text


def main():
    roundtrip = sys.argv[1:] == ["--roundtrip"]
    if not roundtrip and len(sys.argv) != 2:
        sys.exit(__doc__)
    regenerated = {}
    if not roundtrip:
        with open(sys.argv[1], encoding="utf-8") as lines:
            for line in lines:
                if line.strip():
                    entry = json.loads(line)
                    regenerated[entry["date"]] = entry

    merged, missing = [], []
    for path in CHAPTERS:
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        head, body, tail = split(source)
        entries = json.loads(body)
        out = []
        for entry in entries:
            if roundtrip:
                out.append(entry)
                continue
            new = regenerated.get(entry["date"])
            if new is None:
                missing.append(entry["date"])
                out.append(entry)
                continue
            if new["text"] != entry["text"] or new["title"] != entry["title"]:
                sys.exit(f"{entry['date']}: text or title differs from the chapter; not merging")
            out.append({**{k: entry[k] for k in KEPT}, **{k: v for k, v in new.items() if k not in KEPT}})
        updated = head + render(out) + tail
        if roundtrip and updated != source:
            sys.exit(f"roundtrip changed {os.path.basename(path)}")
        if not roundtrip:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(updated)
        merged += out

    if roundtrip:
        print(f"roundtrip ok: {len(merged)} entries in {len(CHAPTERS)} files unchanged")
        return
    if missing:
        sys.exit(f"{len(missing)} entries have no regenerated line (first {missing[0]}); rerun the regeneration")
    report(merged)


def report(entries):
    kinds = collections.Counter(e.get("kind", "journal") for e in entries)
    parts = collections.Counter(min(len(e.get("sections", [])), 4) for e in entries)
    names = collections.Counter((m["name"], m["kind"]) for e in entries for m in e["mentions"])
    tags = collections.Counter(t for e in entries for t in e["tags"])
    opens = sum(len(e.get("opens", [])) for e in entries)
    print(f"entries {len(entries)}  kinds {dict(kinds)}")
    print(f"parts per entry (4 = 4+): {dict(sorted(parts.items()))}")
    print(f"distinct names {len(names)} by kind {dict(collections.Counter(k for _, k in names))}  distinct tags {len(tags)}")
    print(f"top names {[n for (n, _), _ in names.most_common(15)]}")
    print(f"threads opened {opens}  resolves {sum(len(e.get('resolves', [])) for e in entries)}  touches {sum(len(e.get('touches', [])) for e in entries)}")
    problems = []
    for e in entries:
        text = e["text"].lower()
        for m in e["mentions"]:
            if m["name"].lower() not in text and (m.get("writtenSurface") or "\0").lower() not in text:
                problems.append(f"{e['date']}: a name is in neither form in the text")
        mentioned = {m["name"] for m in e["mentions"]}
        for o in e.get("opens", []):
            if not set(o.get("about", [])) <= mentioned:
                problems.append(f"{e['date']}: thread {o['id']} is about a name the entry does not mention")
        if not e["summary"]:
            problems.append(f"{e['date']}: no summary")
    print(f"problems {len(problems)}")
    for line in problems[:40]:
        print("  " + line)


if __name__ == "__main__":
    main()
