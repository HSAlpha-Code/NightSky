param([switch]$BuildBundle)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try {
    python -m unittest tools.test_release
    if ($LASTEXITCODE -ne 0) { throw 'Release gate tests failed.' }
    & "$taskRoot/backend/.venv/Scripts/python.exe" backend/manage.py check
    if ($LASTEXITCODE -ne 0) { throw 'Django configuration checks failed.' }
    & "$taskRoot/backend/.venv/Scripts/python.exe" backend/manage.py test solver providers landmarks curated config.test_legal
    if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed.' }
    Push-Location -LiteralPath "$taskRoot/app"
    try {
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
        flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    } finally { Pop-Location }
    if ($BuildBundle) {
        python tools/release.py check --for-build
    } else {
        python tools/release.py check
    }
    if ($LASTEXITCODE -ne 0) { throw 'Public release inputs remain unresolved; see release/README.md.' }
    if ($BuildBundle) {
        Push-Location -LiteralPath "$taskRoot/app"
        try {
            flutter build appbundle --release --dart-define=SERVER_URL=https://nightsky-backend.vercel.app
            if ($LASTEXITCODE -ne 0) { throw 'Release bundle build failed.' }
            Write-Output 'Candidate bundle built. Complete final device/16 KB checks, then run python tools/release.py check before publication.'
        } finally { Pop-Location }
    }
} finally { Pop-Location }
