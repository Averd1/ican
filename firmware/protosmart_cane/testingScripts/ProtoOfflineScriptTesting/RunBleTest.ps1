param(
    [string]$Address = "",
    [double]$Duration = 20,
    [int]$MinPackets = 10,
    [switch]$WaitStartKey,
    [switch]$NoPlot,
    [switch]$NoAnalyze,
    [switch]$SaveDashboardHtml
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExe = Join-Path $scriptDir ".venv\Scripts\python.exe"
$recorder = Join-Path $scriptDir "TestDataRecorder.py"
$analyzer = Join-Path $scriptDir "AnalyzeBleData.py"
$plotter = Join-Path $scriptDir "TestDataPlotter.py"

if (!(Test-Path $pythonExe)) {
    Write-Error "Local .venv Python not found at $pythonExe"
    exit 1
}

$args = @($recorder, "--duration", "$Duration", "--min-packets", "$MinPackets")

if ($Address -ne "") {
    $args += @("--address", $Address)
}

if ($WaitStartKey) {
    $args += "--wait-start-key"
}

Write-Host "Running BLE test with local .venv..."
Write-Host "Python: $pythonExe"
Write-Host "Duration: $Duration s | MinPackets: $MinPackets"

& $pythonExe @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$latestCsv = Get-ChildItem -Path $scriptDir -Filter "smartcane_ble_v2_*.csv" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $latestCsv) {
    Write-Error "No capture CSV found after recording."
    exit 1
}

Write-Host "Captured CSV: $($latestCsv.FullName)"

if (-not $NoAnalyze) {
    Write-Host "[Stage] Analyze BLE data..."
    & $pythonExe $analyzer --file $latestCsv.FullName --save-json
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not $NoPlot) {
    Write-Host "[Stage] Build Plotly dashboard + virtual signals..."
    $plotArgs = @($plotter, "--file", $latestCsv.FullName, "--save-augmented-csv")
    if ($SaveDashboardHtml) {
        $plotArgs += "--save-html"
    }
    & $pythonExe @plotArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Host "BLE hybrid pipeline complete."
exit 0
