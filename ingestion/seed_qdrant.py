"""M2 bring-up ingestion: embed the knowledge base and upsert to Qdrant.

This is the deterministic path used to get a working system during M2. It reads
the same structured content the PDFs are rendered from (knowledge-base/
documents.py), embeds each section with Ollama `nomic-embed-text`, and upserts
to the Qdrant collection `company_docs`.

The point payload matches exactly what the n8n langchain Qdrant node reads back:
  { "content": "<text>", "metadata": { access_level, doc_name, section, ... } }
and the collection uses a single unnamed 768-dim cosine vector — the default the
langchain QdrantVectorStore expects.

Per M2.2, each chunk is prepended with `Doc Name > Section >` before embedding,
which retrieves materially better than the bare paragraph.

Idempotent: the collection is recreated on each run and point IDs are derived
deterministically from doc_id + chunk_index, so re-running leaves no orphans.

The canonical, locked-decision ingestion path is the n8n workflow
`n8n/workflows/wf-ingest-knowledge-base.json`; this script is the M2 shortcut so
retrieval can be verified headlessly. M3 replaces both with proper PDF-driven,
heading-aware chunking.

Usage:  python -m ingestion.seed_qdrant
Env:    OLLAMA_URL (default http://localhost:11434)
        QDRANT_URL (default http://localhost:6333)
"""

import os
import sys
import uuid
from pathlib import Path

import requests

# Import DOCUMENTS from knowledge-base/documents.py (dir name isn't importable).
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "knowledge-base"))
from documents import DOCUMENTS  # noqa: E402

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434").rstrip("/")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://localhost:6333").rstrip("/")
COLLECTION = "company_docs"
EMBED_MODEL = "nomic-embed-text"
VECTOR_SIZE = 768
NAMESPACE = uuid.UUID("11111111-1111-1111-1111-111111111111")


def embed(text: str) -> list[float]:
    r = requests.post(
        f"{OLLAMA_URL}/api/embeddings",
        json={"model": EMBED_MODEL, "prompt": text},
        timeout=120,
    )
    r.raise_for_status()
    vec = r.json().get("embedding")
    if not vec or len(vec) != VECTOR_SIZE:
        raise RuntimeError(f"unexpected embedding length: {len(vec) if vec else 0}")
    return vec


def recreate_collection() -> None:
    requests.delete(f"{QDRANT_URL}/collections/{COLLECTION}", timeout=30)
    r = requests.put(
        f"{QDRANT_URL}/collections/{COLLECTION}",
        json={"vectors": {"size": VECTOR_SIZE, "distance": "Cosine"}},
        timeout=30,
    )
    r.raise_for_status()


def build_points() -> list[dict]:
    points = []
    for doc in DOCUMENTS:
        for idx, section in enumerate(doc["sections"]):
            prefixed = f"{doc['name']} > {section['heading']} > {section['body']}"
            point_id = str(uuid.uuid5(NAMESPACE, f"{doc['doc_id']}:{idx}"))
            points.append({
                "id": point_id,
                "vector": embed(prefixed),
                "payload": {
                    "content": prefixed,
                    "metadata": {
                        "doc_id": doc["doc_id"],
                        "doc_name": doc["name"],
                        "doc_type": doc["doc_type"],
                        "section": section["heading"],
                        "page": 1,
                        "chunk_index": idx,
                        "access_level": doc["access_level"],
                        "version": doc["version"],
                    },
                },
            })
    return points


def main() -> None:
    recreate_collection()
    points = build_points()
    r = requests.put(
        f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true",
        json={"points": points},
        timeout=120,
    )
    r.raise_for_status()
    count = requests.get(f"{QDRANT_URL}/collections/{COLLECTION}", timeout=30).json()
    n = count["result"]["points_count"]
    safe = sum(1 for p in points if p["payload"]["metadata"]["access_level"] == "customer_safe")
    internal = len(points) - safe
    print(f"upserted {len(points)} points to '{COLLECTION}' (qdrant reports {n})")
    print(f"  customer_safe: {safe}   internal_only: {internal}")


if __name__ == "__main__":
    main()
