#!/usr/bin/env python3
"""
Ingest the danluu/post-mortems collection into a Bedrock Knowledge Base.

Two phases:
  crawl  - parse the danluu README, fetch each linked post-mortem's ORIGINAL
           text, and write one document + metadata sidecar per incident into
           kb/data/.
  sync   - upload kb/data/ to the KB's S3 bucket and start an ingestion job.

Each document carries metadata (company, category, source_url, danluu_summary)
so the agent can cite the real source company + URL during diagnosis (M4).

NOTE (licensing): full original texts are crawled for an INTERNAL lab knowledge
base. Every document records its source_url for attribution; do not redistribute.

Usage:
  python ingest_danluu.py crawl [--limit N]
  python ingest_danluu.py sync --bucket <kb-bucket> --kb-id <id> --ds-id <id> [--region ap-northeast-2]
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time

import requests
from bs4 import BeautifulSoup

README_URL = "https://raw.githubusercontent.com/danluu/post-mortems/master/README.md"
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "data")
UA = {"User-Agent": "ddps-sre-incident-copilot-lab/1.0 (KB ingestion; contact: lab)"}

# A markdown bullet like: [Company](https://url). Description text...
ENTRY_RE = re.compile(r"^\s*\[([^\]]+)\]\((https?://[^)]+)\)\.?\s*(.*)$")
HEADER_RE = re.compile(r"^##\s+(.*)$")
SKIP_SECTIONS = {"Table of Contents", "Other lists of postmortems", "Analysis", "Contributors"}


def parse_readme(md: str):
    """Yield dicts {company, url, summary, category} from the README."""
    category = "Uncategorized"
    for line in md.splitlines():
        h = HEADER_RE.match(line)
        if h:
            category = h.group(1).strip()
            continue
        if category in SKIP_SECTIONS:
            continue
        m = ENTRY_RE.match(line)
        if m:
            yield {
                "company": m.group(1).strip(),
                "url": m.group(2).strip(),
                "summary": m.group(3).strip(),
                "category": category,
            }


def extract_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "header", "footer", "noscript", "form", "aside"]):
        tag.decompose()
    main = soup.find("article") or soup.find("main") or soup.body or soup
    text = main.get_text("\n", strip=True)
    # collapse blank lines
    lines = [ln for ln in (l.strip() for l in text.splitlines()) if ln]
    return "\n".join(lines)


def doc_id(entry) -> str:
    h = hashlib.sha1(entry["url"].encode()).hexdigest()[:10]
    slug = re.sub(r"[^a-z0-9]+", "-", entry["company"].lower()).strip("-")[:40]
    return f"{slug}-{h}"


def crawl(limit=None):
    os.makedirs(DATA_DIR, exist_ok=True)
    md = requests.get(README_URL, headers=UA, timeout=30).text
    entries = list(parse_readme(md))
    if limit:
        entries = entries[:limit]
    print(f"parsed {len(entries)} entries from danluu README")

    ok, fail = 0, 0
    for i, e in enumerate(entries, 1):
        did = doc_id(e)
        try:
            r = requests.get(e["url"], headers=UA, timeout=25)
            ctype = r.headers.get("content-type", "")
            if r.status_code != 200 or "html" not in ctype.lower():
                print(f"[{i}/{len(entries)}] skip {e['company']} ({r.status_code}, {ctype})")
                fail += 1
                continue
            body = extract_text(r.text)
        except Exception as ex:  # noqa: BLE001
            print(f"[{i}/{len(entries)}] FAIL {e['company']}: {ex}")
            fail += 1
            continue

        if len(body) < 200:
            # JS-heavy / blocked / empty page — fall back to the curator summary
            # so the incident is still represented, but flag low fidelity.
            if len(e["summary"]) < 80:
                print(f"[{i}/{len(entries)}] skip {e['company']} (empty page, thin summary)")
                fail += 1
                continue
            body = e["summary"]

        header = (
            f"# {e['company']} — {e['category']}\n"
            f"Source: {e['url']}\n"
            f"Curator summary (danluu/post-mortems): {e['summary']}\n\n"
            f"--- Original post-mortem text ---\n"
        )
        doc_path = os.path.join(DATA_DIR, f"{did}.txt")
        with open(doc_path, "w", encoding="utf-8") as f:
            f.write(header + body)

        # Bedrock KB metadata sidecar
        meta = {
            "metadataAttributes": {
                "company": e["company"],
                "category": e["category"],
                "source_url": e["url"],
                "danluu_summary": e["summary"][:2000],
            }
        }
        with open(doc_path + ".metadata.json", "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False)

        ok += 1
        print(f"[{i}/{len(entries)}] ok   {e['company']} -> {did}.txt ({len(body)} chars)")
        time.sleep(0.4)  # be polite

    print(f"\ncrawl done: {ok} ok, {fail} skipped/failed -> {DATA_DIR}")


def sync(bucket, kb_id, ds_id, region):
    import boto3

    s3 = boto3.client("s3", region_name=region)
    files = [f for f in os.listdir(DATA_DIR) if f.endswith(".txt") or f.endswith(".metadata.json")]
    print(f"uploading {len(files)} objects to s3://{bucket}/danluu/")
    for f in files:
        s3.upload_file(os.path.join(DATA_DIR, f), bucket, f"danluu/{f}")

    bedrock = boto3.client("bedrock-agent", region_name=region)
    job = bedrock.start_ingestion_job(knowledgeBaseId=kb_id, dataSourceId=ds_id)
    jid = job["ingestionJob"]["ingestionJobId"]
    print(f"started ingestion job {jid}; poll status with get_ingestion_job")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crawl")
    c.add_argument("--limit", type=int, default=None)
    s = sub.add_parser("sync")
    s.add_argument("--bucket", required=True)
    s.add_argument("--kb-id", required=True)
    s.add_argument("--ds-id", required=True)
    s.add_argument("--region", default="ap-northeast-2")
    args = ap.parse_args()

    if args.cmd == "crawl":
        crawl(limit=args.limit)
    elif args.cmd == "sync":
        sync(args.bucket, args.kb_id, args.ds_id, args.region)


if __name__ == "__main__":
    main()
