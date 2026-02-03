import os
import io
import json
import uuid
from datetime import datetime
from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import List, Optional
from langchain_text_splitters import RecursiveCharacterTextSplitter
import pypdf
import docx
import boto3
import requests

app = FastAPI(title="Document Chunking Service")

# Configuration
S3_BUCKET = os.getenv("S3_BUCKET", "faro-rag-documents-eu-central-1")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
S3_ENABLED = os.getenv("S3_ENABLED", "false").lower() == "true"

# S3 Client - only create if enabled
s3_client = None
if S3_ENABLED:
    s3_client = boto3.client("s3")

class ChunkRequest(BaseModel):
    text: str
    chunk_size: int = 1000
    chunk_overlap: int = 200
    save_to_s3: bool = True  # Default true when S3 is enabled

class ChunkResponse(BaseModel):
    chunks: List[str]
    total_chunks: int
    document_id: Optional[str] = None
    s3_path: Optional[str] = None

@app.get("/health")
def health_check():
    return {"status": "healthy", "s3_enabled": S3_ENABLED}

def save_chunks_to_s3(chunks: List[str], filename: str = "text") -> tuple[str, str]:
    """Save chunks to S3 and return document_id and s3_path"""
    global s3_client
    
    if not S3_ENABLED:
        raise HTTPException(status_code=400, detail="S3 storage is not enabled. Set S3_ENABLED=true")
    
    if s3_client is None:
        s3_client = boto3.client("s3")
    
    document_id = str(uuid.uuid4())
    timestamp = datetime.now().isoformat()
    
    data = {
        "document_id": document_id,
        "filename": filename,
        "created_at": timestamp,
        "total_chunks": len(chunks),
        "chunks": chunks
    }
    
    s3_key = f"chunks/{document_id}.json"
    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=json.dumps(data),
        ContentType="application/json"
    )
    
    return document_id, f"s3://{S3_BUCKET}/{s3_key}"

@app.post("/chunk/text", response_model=ChunkResponse)
async def chunk_text(request: ChunkRequest):
    """Chunk plain text into smaller pieces"""
    try:
        splitter = RecursiveCharacterTextSplitter(
            chunk_size=request.chunk_size,
            chunk_overlap=request.chunk_overlap
        )
        chunks = splitter.split_text(request.text)
        
        document_id = None
        s3_path = None
        if request.save_to_s3:
            document_id, s3_path = save_chunks_to_s3(chunks)
        
            try:
                trigger_url = "http://embeddings-engine/process/s3"
                # Using the default bucket variable
                requests.post(trigger_url, json={"s3_key": f"chunks/{document_id}.json", "s3_bucket": S3_BUCKET}, timeout=5)
                print(f"Triggered embedding for {document_id}")
            except Exception as e:
                print(f"Warning: Failed to trigger embedding service: {e}")
        
        return {
            "chunks": chunks, 
            "total_chunks": len(chunks),
            "document_id": document_id,
            "s3_path": s3_path
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chunk/file", response_model=ChunkResponse)
async def chunk_file(file: UploadFile = File(...), save_to_s3: bool = True):
    """Upload and chunk a document (PDF, DOCX, TXT)"""
    try:
        content = await file.read()
        text = ""
        
        # Extract text based on file type
        if file.filename.endswith(".pdf"):
            pdf_reader = pypdf.PdfReader(io.BytesIO(content))
            for page in pdf_reader.pages:
                text += page.extract_text() + "\n"
        
        elif file.filename.endswith(".docx"):
            doc = docx.Document(io.BytesIO(content))
            for paragraph in doc.paragraphs:
                text += paragraph.text + "\n"
        
        elif file.filename.endswith(".txt"):
            text = content.decode("utf-8")
        
        else:
            raise HTTPException(status_code=400, detail="Unsupported file type. Use PDF, DOCX, or TXT.")
        
        # Chunk the text
        splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE,
            chunk_overlap=CHUNK_OVERLAP
        )
        chunks = splitter.split_text(text)
        
        document_id = None
        s3_path = None
        if save_to_s3:
            document_id, s3_path = save_chunks_to_s3(chunks, file.filename)
        
            # Trigger Embedding Service
            try:
                # Service name 'embeddings-engine' resolves to the Service IP in K8s
                trigger_url = "http://embeddings-engine/process/s3"
                requests.post(trigger_url, json={"s3_key": f"chunks/{document_id}.json", "s3_bucket": S3_BUCKET}, timeout=5)
                print(f"Triggered embedding for {document_id}")
            except Exception as e:
                print(f"Warning: Failed to trigger embedding service: {e}")
        
        return {
            "chunks": chunks, 
            "total_chunks": len(chunks),
            "document_id": document_id,
            "s3_path": s3_path
        }
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
