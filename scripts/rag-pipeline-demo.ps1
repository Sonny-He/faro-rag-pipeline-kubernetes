# ============================================================
# RAG PIPELINE DEMO - FARO Document Processing
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
Show-Banner "RAG PIPELINE DEMO - FARO"

Write-Host "  Deze demo toont de volledige RAG pipeline:" -ForegroundColor White
Write-Host ""
Write-Host "  Text --> Chunking --> S3 --> Embeddings --> Qdrant" -ForegroundColor Green
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
Write-Host "  Chunking Complete!" -ForegroundColor Green

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
# STEP 3: Generate embeddings
# ------------------------------------------------------------
Show-Step 3 "Generate Embeddings (S3 --> Qdrant)"

$s3Key = "chunks/$script:docId.json"

Write-Host "  Processing document from Step 1..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  S3 Key: $s3Key" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Generating embeddings..." -ForegroundColor Yellow
Write-Host ""

# Call embeddings service
kubectl exec deployment/embeddings-engine -n rag-services -- python -c "import requests, json; r = requests.post('http://localhost:8001/process/s3', json={'s3_key': '$s3Key', 's3_bucket': 'faro-rag-documents-eu-central-1'}); data = r.json(); print('Status:', data['status']); print('Chunks Processed:', data['chunks_processed'])"

Write-Host ""
Write-Host "  Embeddings generated and stored in Qdrant!" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# STEP 4: Query Qdrant
# ------------------------------------------------------------
Show-Step 4 "Verify Data in Qdrant Vector DB"

Write-Host "  Querying Qdrant database for stored vectors..." -ForegroundColor Yellow
Write-Host ""

kubectl exec -n rag-services deployment/embeddings-engine -- python -c "
import requests, json
r = requests.post('http://10.0.11.10:6333/collections/faro_docs/points/scroll', json={'limit': 3, 'with_payload': True, 'with_vector': True})
data = r.json()
points = data['result']['points']
print('Found', len(points), 'vectors in database:')
print()
for p in points:
    text = p['payload']['text'][:60] + '...'
    vector = p['vector'][:8]  # Show first 8 dimensions
    print('  Text:', text)
    print('  Vector (first 8 dims):', [round(v, 4) for v in vector])
    print('  Vector length:', len(p['vector']), 'dimensions')
    print()
"

Write-Host ""
Write-Host "  Text successfully vectorized and stored!" -ForegroundColor Green

Pause-Demo

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
Show-Banner "DEMO COMPLETE"

Write-Host "  The RAG pipeline successfully processed:" -ForegroundColor White
Write-Host ""
Write-Host "    1. Text chunked into manageable pieces" -ForegroundColor Green
Write-Host "    2. Chunks stored in S3 bucket" -ForegroundColor Green
Write-Host "    3. Embeddings generated using AI model" -ForegroundColor Green
Write-Host "    4. Vectors stored in Qdrant database" -ForegroundColor Green
Write-Host ""
Write-Host "  The text is now searchable via semantic similarity!" -ForegroundColor Cyan
Write-Host ""
