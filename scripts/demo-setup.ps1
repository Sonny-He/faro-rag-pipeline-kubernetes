# ============================================================
# DEMO SETUP - Run dit VOOR de presentatie
# ============================================================
# Dit script stelt de AWS credentials in en test de verbinding
# ============================================================

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  🔧 RAG DEMO SETUP                                             ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ------------------------------------------------------------
# STAP 1: AWS Credentials instellen
# ------------------------------------------------------------
Write-Host "📋 STAP 1: Plak je AWS credentials hieronder" -ForegroundColor Yellow
Write-Host ""
Write-Host "   Ga naar AWS Academy → Learner Lab → AWS Details" -ForegroundColor DarkGray
Write-Host "   Klik op 'Show' bij AWS CLI en kopieer de 3 regels" -ForegroundColor DarkGray
Write-Host ""

# Vraag om credentials
$accessKey = Read-Host "AWS_ACCESS_KEY_ID"
$secretKey = Read-Host "AWS_SECRET_ACCESS_KEY"
$sessionToken = Read-Host "AWS_SESSION_TOKEN"

# Stel credentials in
$Env:AWS_ACCESS_KEY_ID = $accessKey
$Env:AWS_SECRET_ACCESS_KEY = $secretKey
$Env:AWS_SESSION_TOKEN = $sessionToken

Write-Host ""
Write-Host "✅ Credentials ingesteld!" -ForegroundColor Green

# ------------------------------------------------------------
# STAP 2: EKS kubeconfig updaten
# ------------------------------------------------------------
Write-Host ""
Write-Host "📋 STAP 2: Verbinden met EKS cluster..." -ForegroundColor Yellow

aws eks update-kubeconfig --name faro-rag-cluster --region eu-central-1

Write-Host "✅ Kubeconfig updated!" -ForegroundColor Green

# ------------------------------------------------------------
# STAP 3: Test verbinding
# ------------------------------------------------------------
Write-Host ""
Write-Host "📋 STAP 3: Testen verbinding met cluster..." -ForegroundColor Yellow
Write-Host ""

$pods = kubectl get pods -n rag-services --no-headers 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Verbinding succesvol! Running pods:" -ForegroundColor Green
    Write-Host ""
    $pods | ForEach-Object { Write-Host "   $_" -ForegroundColor Cyan }
} else {
    Write-Host "❌ Verbinding mislukt. Check je credentials." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# KLAAR
# ------------------------------------------------------------
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ SETUP COMPLETE - Klaar voor demo!                          ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "   Run nu: .\demo\rag-pipeline-demo.ps1" -ForegroundColor White
Write-Host ""
