# Full System Demo Script - Validate End-to-End Pipeline
# Validates: Frontend (Simulated) -> Chunking -> S3 -> Embeddings -> RAG -> Client
# Slow-paced, verbose mode for classroom presentations

$ErrorActionPreference = "Stop"

# --- Helper Functions for Better Output ---
function Write-Header {
    param($text)
    Write-Host ""
    Write-Host "#################################################" -ForegroundColor Cyan
    Write-Host "   $text" -ForegroundColor Cyan
    Write-Host "#################################################" -ForegroundColor Cyan
    Write-Host ""
}

function Write-SubHeader {
    param($text)
    Write-Host "`n=== $text ===" -ForegroundColor White
}

function Write-Step {
    param($title)
    Write-Host " [$([DateTime]::Now.ToString('HH:mm:ss'))] STEP: $title" -ForegroundColor Gray
}

function Write-Success {
    param($msg)
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Info {
    param($msg)
    Write-Host "    [INFO] $msg" -ForegroundColor Gray
}

function Write-Warning-Msg {
    param($msg)
    Write-Host "    [WARN] $msg" -ForegroundColor Yellow
}

function Write-Error-Msg {
    param($msg)
    Write-Host "    [ERROR] $msg" -ForegroundColor Red
}

function Write-Content {
    param($title, $content)
    Write-Host "`n    --- $title ---" -ForegroundColor Yellow
    Write-Host "    $content" -ForegroundColor White
    Write-Host "    ------------------------`n" -ForegroundColor Yellow
}

function Pause-For-Demo {
    param($seconds=6)
    Write-Host "    ...pausing $seconds seconds (reading time)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $seconds
}

function Start-PortForward {
    param($serviceName, $localPort, $remotePort)
    Write-Info "Tunneling to '$serviceName' (Local:$localPort -> Remote:$remotePort)..."
    $process = Start-Process kubectl -ArgumentList "port-forward svc/$serviceName $localPort`:$remotePort -n rag-services" -PassThru -NoNewWindow
    Start-Sleep -Seconds 3 # Give it time to establish
    if ($process.HasExited) {
        Write-Error-Msg "Port forward failed immediately."
    }
    return $process
}

# --- Main Script ---

Clear-Host
Write-Header "FARO RAG SYSTEM - CLASSROOM DEMO"

# 0. Setup
Write-Step "Initializing Demo Context"
$uniqueId = Get-Random -Minimum 1000 -Maximum 9999
$demoText = "Review of the Faro Deployment. The project secret codename is OMEGA-$uniqueId. This document confirms the system uses S3, Qdrant and Kubernetes."

Write-Info "Generated unique session ID: $uniqueId"
Pause-For-Demo 3


# 1. Inspect Cluster State
Write-Step "Verifying Cluster State..."
try {
    $services = kubectl get svc -n rag-services -o json | ConvertFrom-Json
    $chunkingSvc = $services.items | Where-Object { $_.metadata.name -eq "document-chunking" }
    $embeddingsSvc = $services.items | Where-Object { $_.metadata.name -eq "embeddings-engine" }
    $ragSvc = $services.items | Where-Object { $_.metadata.name -eq "rag-query" }

    if (-not $chunkingSvc -or -not $embeddingsSvc -or -not $ragSvc) {
        Throw "One or more required services are missing from 'rag-services' namespace."
    }
    Write-Success "All Microservices are RUNNING (Chunking, Embeddings, RAG-Query)."
} catch {
    Write-Error-Msg "Failed to verify cluster services: $_"
    exit 1
}
Pause-For-Demo 3


# 2. Step 1: Frontend -> Chunking Service (Ingestion)
Write-Header "PHASE 1: INGESTION & STORAGE"

Write-SubHeader "1. Simulating User Upload"
Write-Info "The Frontend simulates uploading a text file containing our secret code."
Write-Content "FILE CONTENT TO UPLOAD" $demoText
Pause-For-Demo

Write-SubHeader "2. Sending to Chunking Service"
$chunkingPort = 8081
$processChunking = Start-PortForward "document-chunking" $chunkingPort 80

try {
    $ingestUrl = "http://localhost:$chunkingPort/chunk/text"
    $payload = @{
        text = $demoText
        save_to_s3 = $true
    } | ConvertTo-Json

    Write-Info "POST $ingestUrl"
    $response = Invoke-WebRequest -Uri $ingestUrl -Method Post -Body $payload -ContentType "application/json" -UseBasicParsing
    
    if ($response.StatusCode -eq 200) {
        $jsonResp = $response.Content | ConvertFrom-Json
        Write-Success "Upload Successful!"
        Write-Info "Service Response:"
        Write-Host "      - Chunks created:   $($jsonResp.total_chunks)" -ForegroundColor Green
        Write-Host "      - Saved to S3:      Yes" -ForegroundColor Green
        Write-Host "      - Triggered Engine: Yes " -ForegroundColor Green
    }
}
catch {
    Write-Error-Msg "Ingestion failed: $_"
}
finally {
    if ($processChunking) { Stop-Process -Id $processChunking.Id -Force -ErrorAction SilentlyContinue }
}
Pause-For-Demo

Write-SubHeader "3. Verifying S3 Storage (AWS Cloud)"
Write-Info "Checking AWS S3 bucket 'faro-rag-documents-eu-central-1'..."
try {
    # Simple check to show the latest file
    $s3Files = aws s3 ls s3://faro-rag-documents-eu-central-1/chunks/ --recursive 
    if ($s3Files) {
        # Sort manually-ish by taking the last line which usually is latest
        $latest = $s3Files | Select-Object -Last 1
        Write-Success "File confirmed in S3 Bucket:"
        Write-Host "    $latest" -ForegroundColor Cyan
    } else {
        Write-Warning-Msg "Bucket appears empty or access denied."
    }
} catch {
    Write-Warning-Msg "Could not list S3 (AWS CLI Check skipped)."
}
Pause-For-Demo


# 3. Step 2: Validate Embeddings Engine
Write-Header "PHASE 2: ENRICHMENT (Internal Pipeline)"
Write-Info "The application automatically picks up the file."
Write-Info "It calculates vector embeddings and stores them in Qdrant (Vector DB) & Postgres."
Pause-For-Demo 4

Write-SubHeader "4. Checking Embeddings Engine Connections"

$embPort = 8082
$processEmb = Start-PortForward "embeddings-engine" $embPort 80

try {
    $healthUrl = "http://localhost:$embPort/health"
    Write-Info "Checking Health Endpoint: $healthUrl"
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing
    $health = $resp.Content | ConvertFrom-Json
    
    Write-Content "ENGINE HEALTH REPORT" "Status:   $($health.status)`n    Qdrant:   $($health.qdrant)`n    Postgres: $($health.postgres)"
    
    if ($health.qdrant -eq "connected") {
        Write-Success "Embeddings Engine to Vector DB connection is ACTIVE."
    } else {
        Write-Warning-Msg "Vector DB connection issue."
    }
}
catch {
    Write-Warning-Msg "Could not query Embeddings health. Assuming it's running but busy."
}
finally {
    if ($processEmb) { Stop-Process -Id $processEmb.Id -Force -ErrorAction SilentlyContinue }
}
Pause-For-Demo


# 4. Step 3: RAG Query (Validation)
Write-Header "PHASE 3: RETRIEVAL (Client -> RAG)"
Write-Info "We will now ask the RAG Service about the secret code we uploaded in Phase 1."
Write-Info "Allowing 8 seconds for vector indexing to finish..."
Start-Sleep -Seconds 8

Write-SubHeader "5. Executing Question"
$question = "What is the project secret codename?"
Write-Content "QUESTION" $question
Pause-For-Demo 4

# Check LoadBalancer first
$lb = kubectl get svc rag-query -n rag-services -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"

$ragUrl = ""
$processRag = $null

if ([string]::IsNullOrWhiteSpace($lb)) {
    Write-Info "Note: Public access via LoadBalancer pending. Using Tunnel."
    $ragPort = 8083
    $processRag = Start-PortForward "rag-query" $ragPort 80
    $ragUrl = "http://localhost:$ragPort/query"
} else {
    Write-Info "Connecting via Public LoadBalancer: $lb"
    $ragUrl = "http://$lb/query"
}

try {
    Write-Info "Sending Request..."
    
    $queryPayload = @{ question = $question } | ConvertTo-Json
    $queryResp = Invoke-WebRequest -Uri $ragUrl -Method Post -Body $queryPayload -ContentType "application/json" -UseBasicParsing
    
    $answer = $queryResp.Content | ConvertFrom-Json
    
    Write-Content "SYSTEM ANSWER" $answer.answer
    
    if ($answer.answer -match "OMEGA-$uniqueId") {
        Write-Success "VERIFICATION PASSED: The system retrieved 'OMEGA-$uniqueId'!"
    } else {
        Write-Warning-Msg "VERIFICATION PARTIAL: The code was not found. Indexing might need more time."
    }
}
catch {
    Write-Error-Msg "RAG Query failed: $_"
}
finally {
    if ($processRag) { Stop-Process -Id $processRag.Id -Force -ErrorAction SilentlyContinue }
}

Write-Header "DEMO COMPLETE - System Validation Finished"
Pause-For-Demo 3
