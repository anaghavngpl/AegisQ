# AegisQ Backend Startup Automation

$port = 8000
$projectId = "chat-app-f64a3"

Write-Host "🚀 Starting AegisQ Backend Setup..." -ForegroundColor Cyan

# 1. Clear Port Conflict
Write-Host "🔍 Checking for processes on port $port..." -ForegroundColor Yellow
$processId = (Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue).OwningProcess
if ($processId) {
    Write-Host "⚔️ Terminating stale process ID: $processId" -ForegroundColor Red
    Stop-Process -Id $processId -Force
} else {
    Write-Host "✅ Port $port is clear." -ForegroundColor Green
}

# 2. Validate serviceAccountKey.json
$keyPath = "serviceAccountKey.json"
if (Test-Path $keyPath) {
    $keyContent = Get-Content $keyPath | ConvertFrom-Json
    if ($keyContent.project_id -ne $projectId) {
        Write-Host "⚠️ WARNING: serviceAccountKey.json is for project '$($keyContent.project_id)'." -ForegroundColor Red
        Write-Host "👉 Please replace it with a key for '$projectId' from your Firebase Console." -ForegroundColor White
    } else {
        Write-Host "✅ Credentials match project: $projectId" -ForegroundColor Green
    }
} else {
    Write-Host "❌ ERROR: serviceAccountKey.json not found!" -ForegroundColor Red
    Write-Host "👉 Download it from Firebase Console -> Service Accounts and place it in the backend folder." -ForegroundColor White
}

# 3. Start the server
Write-Host "🎬 Launching AegisQ Secure Server..." -ForegroundColor Cyan
python -m uvicorn main:app --host 0.0.0.0 --port $port
