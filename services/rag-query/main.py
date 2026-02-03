import os
import time
from typing import Any, Dict, List, Optional
import psycopg2
from prometheus_client import make_asgi_app, Histogram, Gauge

import boto3
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from qdrant_client import QdrantClient
from prometheus_fastapi_instrumentator import Instrumentator

APP_NAME = "rag-query"

# Dependencies
EMBEDDINGS_ENGINE_URL = os.getenv("EMBEDDINGS_ENGINE_URL", "http://localhost:8001")
EMBEDDINGS_ENDPOINT = os.getenv("EMBEDDINGS_ENDPOINT", "/embed")

QDRANT_URL = os.getenv("QDRANT_URL", "http://10.0.11.10:6333")
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION", "faro_docs")

# S3 Config
S3_BUCKET = os.getenv("S3_BUCKET", "")
AWS_REGION = os.getenv("AWS_REGION", "eu-central-1")
s3 = boto3.client("s3", region_name=AWS_REGION) if S3_BUCKET else None

# LLM Config
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.openai.com/v1")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-4o-mini")

app = FastAPI(title=APP_NAME)

Instrumentator().instrument(app).expose(app)

@app.on_event("startup")
async def startup():
    
    pass
    
# Histogram for Speed (Latency)
SEARCH_LATENCY = Histogram(
    "rag_search_latency_seconds",
    "Time spent searching vector database",
    ["database"] # Label: 'qdrant' or 'postgres'
)

# Gauge for Accuracy Proxy (Overlap)
SEARCH_OVERLAP = Gauge(
    "rag_search_overlap_ratio",
    "Percentage of result overlap between Qdrant and Postgres (0.0 to 1.0)"
)

qdrant = QdrantClient(url=QDRANT_URL)


class QueryRequest(BaseModel):
    question: str = Field(..., min_length=3, max_length=2000)
    top_k: int = Field(5, ge=1, le=20)


class Source(BaseModel):
    score: float
    chunk_id: str
    document_id: Optional[str] = None
    title: Optional[str] = None
    s3_key: Optional[str] = None


class QueryResponse(BaseModel):
    answer: str
    sources: List[Source]
    timings_ms: Dict[str, int]

def get_postgres_conn():
    try:
        return psycopg2.connect(
            host=os.getenv("PG_HOST"),
            database=os.getenv("PG_DB"),
            user=os.getenv("PG_USER"),
            password=os.getenv("PG_PASSWORD")
        )
    except Exception as e:
        print(f"ERROR: Postgres connection failed: {e}")
        return None

@app.get("/health")
def health():
    return {"status": "ok", "service": APP_NAME}


async def get_query_embedding(question: str) -> List[float]:
    url = EMBEDDINGS_ENGINE_URL.rstrip("/") + EMBEDDINGS_ENDPOINT
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(url, json={"text": question})
    if r.status_code != 200:
        print(f"ERROR: Embedding service failed: {r.text}")
        raise HTTPException(status_code=502, detail=f"Embedding service error: {r.text}")
    data = r.json()
    emb = data.get("embedding")
    if not isinstance(emb, list) or not emb:
        raise HTTPException(status_code=502, detail="Embedding service returned no embedding")
    return emb


def fetch_text_from_s3(s3_key: str) -> str:
    if not s3 or not S3_BUCKET:
        print(f"WARNING: Cannot fetch {s3_key}, S3_BUCKET not set.")
        return ""
    try:
        obj = s3.get_object(Bucket=S3_BUCKET, Key=s3_key)
        content = obj["Body"].read().decode("utf-8", errors="replace")
        return content
    except Exception as e:
        print(f"ERROR: S3 fetch failed for {s3_key}: {e}")
        return ""


async def call_llm(question: str, context: str) -> str:
    if not LLM_API_KEY:
        return (
            "Answer: LLM_API_KEY not set. Retrieval worked; here is a context preview.\n\n"
            f"{context[:1000]}\n\n"
        )

    headers = {"Authorization": f"Bearer {LLM_API_KEY}", "Content-Type": "application/json"}

    # Simplified Prompt: No citations requested
    messages = [
        {
            "role": "system",
            "content": (
                "You are a helpful RAG assistant. "
                "Answer the user's question using ONLY the provided context below. "
                "If the context does not contain the answer, state that you cannot find the information."
            ),
        },
        {
            "role": "user",
            "content": (
                f"CONTEXT:\n{context}\n\n"
                f"QUESTION:\n{question}\n"
            ),
        },
    ]

    body = {"model": LLM_MODEL, "messages": messages, "temperature": 0.2}

    async with httpx.AsyncClient(timeout=60) as client:
        r = await client.post(f"{LLM_BASE_URL.rstrip('/')}/chat/completions", json=body, headers=headers)

    if r.status_code != 200:
        print(f"ERROR: LLM failed: {r.text}")
        raise HTTPException(status_code=502, detail=f"LLM error: {r.text}")

    data = r.json()
    try:
        return data["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"ERROR: Parsing LLM response failed: {e}")
        raise HTTPException(status_code=502, detail="LLM returned unexpected response")


@app.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest):
    t0 = time.time()
    print(f"INFO: Processing query: {req.question}")

    # 1) Embed
    t_embed0 = time.time()
    emb = await get_query_embedding(req.question)
    t_embed1 = time.time()

    # 2) Search - PRIMARY (Qdrant)
    t_q0 = time.time()
    hits = qdrant.search(
        collection_name=QDRANT_COLLECTION,
        query_vector=emb,
        limit=req.top_k,
        with_payload=True,
        with_vectors=False,
    )
    t_q1 = time.time()
    
    # Record Primary Metric
    qdrant_latency = t_q1 - t_q0
    SEARCH_LATENCY.labels(database="qdrant").observe(qdrant_latency)
    
    # Save IDs for comparison
    qdrant_ids = {str(h.id) for h in hits}

    # 3) Search - SHADOW (Postgres)
    # This block is strictly for metrics. It does NOT affect the 'hits' variable used for the answer.
    pg_conn = get_postgres_conn()
    if pg_conn:
        try:
            t_p0 = time.time()
            with pg_conn.cursor() as cur:
                query_sql = """
                    SELECT id 
                    FROM embeddings 
                    ORDER BY vector <=> %s 
                    LIMIT %s;
                """
                # Pass vector as string for pgvector
                cur.execute(query_sql, (str(emb), req.top_k))
                pg_hits = cur.fetchall()
            t_p1 = time.time()
            
            # Record Shadow Metrics
            pg_latency = t_p1 - t_p0
            SEARCH_LATENCY.labels(database="postgres").observe(pg_latency)
            
            # Compare IDs (Overlap)
            pg_ids = {str(row[0]) for row in pg_hits}
            intersection = qdrant_ids.intersection(pg_ids)
            
            overlap = len(intersection) / req.top_k if req.top_k > 0 else 0.0
            SEARCH_OVERLAP.set(overlap)
            
            print(f"COMPARISON: Qdrant={qdrant_latency:.3f}s, PG={pg_latency:.3f}s, Overlap={overlap*100:.1f}%")

        except Exception as e:
            # SAFETY: If Postgres fails, we just log it and continue. The user still gets their answer.
            print(f"ERROR: Postgres shadow search failed: {e}")
        finally:
            pg_conn.close()
    else:
        print("WARNING: Skipping Postgres search (No Connection)")

    # 4) Build Context
    # Note: We are using 'hits' (from Qdrant) just like before.
    contexts: List[str] = []
    sources: List[Source] = []

    if not hits:
        # Fast exit if Qdrant found nothing
        return QueryResponse(
            answer="Answer: No relevant documents found.",
            sources=[],
            timings_ms={
                "embed": int((t_embed1 - t_embed0) * 1000),
                "search": int((t_q1 - t_q0) * 1000),
                "llm": 0,
                "total": int((time.time() - t0) * 1000),
            },
        )

    for h in hits:
        payload = h.payload or {}
        chunk_id = str(h.id)
        
        text = payload.get("text") or payload.get("chunk_text")
        s3_key = payload.get("s3_key") or payload.get("s3Key") or payload.get("key")

        if not text and s3_key:
            print(f"INFO: Payload text empty for {chunk_id}, fetching from S3: {s3_key}")
            text = fetch_text_from_s3(str(s3_key))

        if not text:
            print(f"WARNING: No text found for chunk {chunk_id}. Skipping.")
            continue

        src = Source(
            score=float(h.score),
            chunk_id=chunk_id,
            document_id=payload.get("document_id") or payload.get("doc_id"),
            title=payload.get("title"),
            s3_key=str(s3_key) if s3_key else None,
        )
        sources.append(src)
        contexts.append(f"Content: {text}")

    context_block = "\n\n---\n\n".join(contexts)[:15000]
    
    # DEBUG LOGGING
    print(f"DEBUG: Context Size: {len(context_block)} chars")

    # 5) LLM
    t_llm0 = time.time()
    if not context_block:
         answer = "Error: Found documents but failed to extract text content."
    else:
         answer = await call_llm(req.question, context_block)
    t_llm1 = time.time()

    return QueryResponse(
        answer=answer,
        sources=sources,
        timings_ms={
            "embed": int((t_embed1 - t_embed0) * 1000),
            "search": int((t_q1 - t_q0) * 1000), # Kept as "search" for frontend compatibility
            "llm": int((t_llm1 - t_llm0) * 1000),
            "total": int((time.time() - t0) * 1000),
        },
    )