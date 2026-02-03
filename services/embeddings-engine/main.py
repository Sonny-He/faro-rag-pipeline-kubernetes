import os
import httpx
import boto3
import json
import uuid
import psycopg2
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from qdrant_client import QdrantClient
from qdrant_client.http import models

app = FastAPI(title="Embeddings Engine Service")

# --- Configuration ---
PORTKEY_API_URL = "https://api.portkey.ai/v1/embeddings"
PORTKEY_API_KEY = os.getenv("PORTKEY_API_KEY")

# Qdrant Config
QDRANT_URL = os.getenv("QDRANT_URL", "http://10.0.11.10:6333")
QDRANT_COLLECTION = os.getenv("QDRANT_COLLECTION", "faro_docs")

# AWS Config
AWS_REGION = os.getenv("AWS_REGION", "eu-central-1")
S3_CLIENT = boto3.client('s3', region_name=AWS_REGION)

# Postgres Config
PG_HOST = os.getenv("PG_HOST")
PG_DB = os.getenv("PG_DB", "vectordb")
PG_USER = os.getenv("PG_USER", "vectoradmin")
PG_PASSWORD = os.getenv("PG_PASSWORD")

# Global Client Placeholder
_qdrant_client = None

def get_postgres_conn():
    """Establishes connection to PostgreSQL"""
    try:
        
        host = PG_HOST.split(":")[0] if PG_HOST else None
        
        conn = psycopg2.connect(
            host=host,
            database=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        return conn
    except Exception as e:
        print(f"Postgres connection failed: {e}")
        return None

def init_postgres():
    """Ensures vector extension and table exist"""
    conn = get_postgres_conn()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS embeddings (
                    id UUID PRIMARY KEY,
                    vector vector(1024),
                    text TEXT,
                    source_file TEXT
                );
            """)
            conn.commit()
            print("Postgres table initialized")
            cur.close()
            conn.close()
        except Exception as e:
            print(f"Postgres init failed: {e}")

# Initialize Postgres on startup
init_postgres()

def get_qdrant_client():
    """Tries to connect to Qdrant. Returns client or None."""
    global _qdrant_client
    if _qdrant_client:
        return _qdrant_client
    
    try:
        client = QdrantClient(url=QDRANT_URL, timeout=10.0) 
        
        # Get list of existing collections
        existing_collections = client.get_collections().collections
        exists = any(c.name == QDRANT_COLLECTION for c in existing_collections)
        
        if exists:
             print(f"Connected to existing collection '{QDRANT_COLLECTION}'")
        else:
            try:
                client.create_collection(
                    collection_name=QDRANT_COLLECTION,
                    vectors_config=models.VectorParams(size=1024, distance=models.Distance.COSINE),
                )
                print(f"Created new collection '{QDRANT_COLLECTION}'")
            except Exception as e:
                # If another pod created it in the meantime, ignore the error
                if "already exists" in str(e) or "Conflict" in str(e):
                    print(f"✅ Collection '{QDRANT_COLLECTION}' already exists (race condition handled)")
                else:
                    raise e
        
        _qdrant_client = client
        return _qdrant_client
    except Exception as e:
        print(f"Qdrant connection failed: {e}")
        return None

# --- Models ---
class EmbeddingRequest(BaseModel):
    text: str
    metadata: Optional[dict] = {}

class EmbeddingResponse(BaseModel):
    embedding: List[float]
    stored_id: Optional[str] = None

class S3ProcessRequest(BaseModel):
    s3_key: str
    s3_bucket: str

class ProcessResponse(BaseModel):
    status: str
    chunks_processed: int
    doc_id: str

# --- Endpoints ---

@app.get("/health")
def health_check():
    # Attempt to connect now if we aren't already
    q_client = get_qdrant_client()
    pg_conn = get_postgres_conn()
    
    status = {
        "status": "healthy", 
        "qdrant": "connected" if q_client else "disconnected",
        "postgres": "connected" if pg_conn else "disconnected"
    }
    
    if pg_conn:
        pg_conn.close()
        
    return status

@app.post("/embed", response_model=EmbeddingResponse)
async def generate_embedding(request: EmbeddingRequest):
    headers = {
        "Content-Type": "application/json",
        "x-portkey-api-key": PORTKEY_API_KEY
    }
    payload = { "input": [request.text], "encoding_format": "float" }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(PORTKEY_API_URL, json=payload, headers=headers, timeout=30.0)
            response.raise_for_status()
            vector = response.json()["data"][0]["embedding"]
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Embedding API Error: {str(e)}")

    point_id = str(uuid.uuid4())
    stored_id = point_id

    return {"embedding": vector, "stored_id": stored_id}

@app.post("/process/s3", response_model=ProcessResponse)
async def process_s3_file(request: S3ProcessRequest):
    # This endpoint checks database connections
    q_db = get_qdrant_client()
    if not q_db:
        print("Warning: Qdrant unavailable, proceeding anyway...")

    try:
        response = S3_CLIENT.get_object(Bucket=request.s3_bucket, Key=request.s3_key)
        file_content = response['Body'].read().decode('utf-8')
        data = json.loads(file_content)
        chunks = data.get("chunks", [])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read S3 file: {str(e)}")

    processed_count = 0
    headers = { "Content-Type": "application/json", "x-portkey-api-key": PORTKEY_API_KEY }
    
    # Establish PG connection for the batch
    pg_conn = get_postgres_conn()

    async with httpx.AsyncClient() as client:
        for chunk_text in chunks:
            try:
                payload = { "input": [chunk_text], "encoding_format": "float" }
                api_res = await client.post(PORTKEY_API_URL, json=payload, headers=headers, timeout=30.0)
                api_res.raise_for_status()
                vector = api_res.json()["data"][0]["embedding"]
                
                point_id = str(uuid.uuid4())

                # Save Qdrant
                if q_db:
                    q_db.upsert(
                        collection_name=QDRANT_COLLECTION,
                        points=[models.PointStruct(id=point_id, vector=vector, payload={"text": chunk_text, "source_file": request.s3_key})]
                    )

                # Save Postgres
                if pg_conn:
                    with pg_conn.cursor() as cur:
                        cur.execute(
                            "INSERT INTO embeddings (id, vector, text, source_file) VALUES (%s, %s, %s, %s)",
                            (point_id, str(vector), chunk_text, request.s3_key)
                        )
                    pg_conn.commit()

                processed_count += 1
            except Exception as e:
                print(f"Error processing chunk: {e}")
                continue 

    if pg_conn:
        pg_conn.close()

    return { "status": "completed", "chunks_processed": processed_count, "doc_id": request.s3_key }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)