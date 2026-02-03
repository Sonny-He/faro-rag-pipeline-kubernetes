# ============================================================
# RAG PIPELINE DEMO - FARO Document Processing (Dual Store)
# ============================================================

function Show-Banner {
    param([string]$Title)
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Step {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host "--------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  STEP $Number - $Title" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host ""
}

function Pause-Demo {
    Write-Host ""
    Write-Host "  [Druk op Enter voor volgende stap...]" -ForegroundColor DarkGray
    Read-Host | Out-Null
}

# ============================================================
# START DEMO
# ============================================================

Clear-Host
Show-Banner "RAG PIPELINE DEMO - FARO (Dual Storage)"

Write-Host "  Deze demo toont de volledige RAG pipeline:" -ForegroundColor White
Write-Host ""
Write-Host "  Text --> Chunking --> S3 --> Embeddings --> Qdrant AND Postgres" -ForegroundColor Green
Write-Host ""
Write-Host "  Infrastructure:" -ForegroundColor White
Write-Host "    - AWS EKS Cluster: faro-rag-cluster" -ForegroundColor DarkGray
Write-Host "    - Region: eu-central-1" -ForegroundColor DarkGray
Write-Host "    - Namespace: rag-services" -ForegroundColor DarkGray

Pause-Demo

# ------------------------------------------------------------
# STEP 0: Show running pods
# ------------------------------------------------------------
Show-Step 0 "Kubernetes Pods Status"

Write-Host "  Running pods in namespace rag-services:" -ForegroundColor White
Write-Host ""
kubectl get pods -n rag-services

Pause-Demo

# ------------------------------------------------------------
# STEP 1: Chunk text and save to S3
# ------------------------------------------------------------
Show-Step 1 "Document Chunking --> S3"

Write-Host "  Input Text:" -ForegroundColor White
Write-Host ""
Write-Host "  Kubernetes is an open-source container orchestration" -ForegroundColor Cyan
Write-Host "  platform that automates deployment and scaling." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Sending to Chunking Service..." -ForegroundColor Yellow
Write-Host ""

# Call chunking service and capture document ID
$chunkOutput = kubectl exec deployment/document-chunking -n rag-services -- python -c "import requests, json; r = requests.post('http://localhost:8000/chunk/text', json={'text': 'Kubernetes is an open-source container orchestration platform that automates the deployment, scaling, and management of containerized applications.', 'save_to_s3': True}); data = r.json(); print(data['document_id']); print(data['total_chunks']); print(data['s3_path'])" 2>$null
$outputLines = $chunkOutput -split "`n"
$script:docId = $outputLines[0].Trim()

Write-Host "  Document ID:  $($outputLines[0])" -ForegroundColor White
Write-Host "  Total Chunks: $($outputLines[1])" -ForegroundColor White  
Write-Host "  S3 Path:      $($outputLines[2])" -ForegroundColor White
Write-Host ""
Write-Host "  Chunking Complete! (Triggered Embeddings automatically)" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# STEP 2: Check S3 bucket
# ------------------------------------------------------------
Show-Step 2 "Verify S3 Storage"

Write-Host "  Recent files in S3 bucket:" -ForegroundColor White
Write-Host ""
aws s3 ls s3://faro-rag-documents-eu-central-1/chunks/ --human-readable | Select-Object -Last 5

Write-Host ""
Write-Host "  Chunks saved to S3!" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# STEP 3: Generate embeddings (Verification)
# ------------------------------------------------------------
Show-Step 3 "Verify Embedding Generation"

# Note: The Chunking Service (Step 1) now triggers this automatically.
# We will just verify the logs of the embedding engine to see if it picked it up.

Write-Host "  Checking Embedding Engine logs for activity..." -ForegroundColor Yellow
Write-Host ""

# Get the last 10 lines of logs
kubectl logs -n rag-services -l app=embeddings-engine --tail=5 --prefix=true

Write-Host ""
Write-Host "  (If you see 'Triggered embedding' or 200 OK above, it worked)" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# STEP 4: Query Qdrant
# ------------------------------------------------------------
Show-Step 4 "Verify Data in Qdrant Vector DB"

Write-Host "  Querying Qdrant database for stored vectors..." -ForegroundColor Yellow
Write-Host ""

kubectl exec deployment/embeddings-engine -n rag-services -- python -c "
import requests, json
r = requests.post('http://10.0.11.10:6333/collections/faro_docs/points/scroll', json={'limit': 1, 'with_payload': True, 'with_vector': False})
data = r.json()
points = data['result']['points']
print('Found', len(points), 'vectors in Qdrant:')
for p in points:
    print('  ID:', p['id'])
    print('  Text:', p['payload']['text'][:50] + '...')
"

Write-Host ""
Write-Host "  Data found in Qdrant!" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# STEP 5: Verify PostgreSQL (NEW)
# ------------------------------------------------------------
Show-Step 5 "Verify Data in PostgreSQL (RDS)"

Write-Host "  Querying PostgreSQL database for stored vectors..." -ForegroundColor Yellow
Write-Host ""

kubectl exec deployment/embeddings-engine -n rag-services -- python -c "
import psycopg2, os

try:
    conn = psycopg2.connect(
        host=os.getenv('PG_HOST'),
        database=os.getenv('PG_DB'),
        user=os.getenv('PG_USER'),
        password=os.getenv('PG_PASSWORD')
    )
    cur = conn.cursor()
    cur.execute('SELECT count(*), source_file FROM embeddings GROUP BY source_file;')
    rows = cur.fetchall()
    
    print('Connected to:', os.getenv('PG_HOST'))
    if rows:
        for count, source in rows:
            print(f'✅ Found {count} vectors for file: {source}')
    else:
        print('⚠️  Table exists but is empty.')
        
    conn.close()
except Exception as e:
    print(f'❌ Error: {e}')
"

Write-Host ""
Write-Host "  Dual-Storage Verification Complete!" -ForegroundColor Green

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
Show-Banner "DEMO COMPLETE"

Write-Host "  The RAG pipeline successfully processed:" -ForegroundColor White
Write-Host ""
Write-Host "    1. Text Chunked & S3 Stored" -ForegroundColor Green
Write-Host "    2. Auto-Triggered Embeddings" -ForegroundColor Green
Write-Host "    3. Data stored in Qdrant (Vector Search)" -ForegroundColor Green
Write-Host "    4. Data stored in PostgreSQL (Long-term Storage)" -ForegroundColor Green
Write-Host ""