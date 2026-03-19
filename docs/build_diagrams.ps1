# Renders Mermaid diagrams to PNG via mermaid.ink, then rebuilds the DOCX
# with the PNGs embedded in place of the ASCII flow sections.

$base = "$PSScriptRoot\.."
$base = (Resolve-Path $base).Path
$diagDir = "$base\docs\diagrams"
New-Item -ItemType Directory -Force -Path $diagDir | Out-Null

# ── Mermaid.ink helper ─────────────────────────────────────────────────────────
function Get-DiagramPng([string]$name, [string]$definition) {
    $outFile = "$diagDir\$name.png"
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($definition)
    $b64     = [Convert]::ToBase64String($bytes)
    $url     = "https://mermaid.ink/img/$b64"
    Write-Host "  Rendering $name ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        Write-Host "    -> $outFile ($([int](Get-Item $outFile).Length / 1024) KB)"
    } catch {
        Write-Warning "    FAILED for $name : $_"
    }
}

# ── Diagram definitions ────────────────────────────────────────────────────────

Write-Host "Rendering diagrams..."

# 1. Architecture Overview
Get-DiagramPng "01_architecture" @"
graph TD
  Browser["Browser"]
  subgraph CF["Cloudflare Edge"]
    CFEdge["TLS termination<br/>project.beckersd.com<br/>argocd.beckersd.com"]
  end
  subgraph K8s["Kubernetes Cluster  cp1 · worker1 · worker2"]
    CFPod["db-cloudflared<br/>db-stack ns"]
    Ingress["db-ingress-nginx<br/>NodePort 30080 / 30443"]
    subgraph App["db-stack namespace"]
      Frontend["db-frontend<br/>Apache · 1 replica"]
      API["db-api<br/>FastAPI · 2 replicas"]
      DB[("db-postgres<br/>StatefulSet + PVC")]
    end
    subgraph Mon["monitoring namespace"]
      Prom["db-prometheus<br/>NodePort 30090"]
      Grafana["db-grafana<br/>NodePort 30030"]
      KSM["db-kube-state-metrics"]
      NE["db-node-exporter<br/>DaemonSet"]
    end
    subgraph ArgoNS["argocd namespace"]
      ArgoCD["db-argocd-server"]
    end
  end
  GitHub["GitHub<br/>dabeastnet/db-k8s-stack"]

  Browser -->|"HTTPS"| CFEdge
  CFEdge <-->|"HTTP tunnel"| CFPod
  CFPod --> Ingress
  Ingress -->|"Host: project / path: /api"| API
  Ingress -->|"Host: project / path: /"| Frontend
  Ingress -->|"Host: argocd.beckersd.com"| ArgoCD
  API -->|"SQL"| DB
  Prom -->|"scrape /metrics"| API
  Prom -->|"scrape :8080"| KSM
  Prom -->|"scrape :9100"| NE
  Grafana -->|"PromQL"| Prom
  ArgoCD -->|"poll + sync k8s/"| GitHub
"@

# 2. Application Startup Sequence
Get-DiagramPng "02_startup_sequence" @"
sequenceDiagram
  participant V as vagrant up
  participant CC as provision-common.sh<br/>(all 3 nodes)
  participant CP as provision-master.sh<br/>(cp1)
  participant W as provision-worker.sh<br/>(worker1 + worker2)
  participant API as db-api container
  participant DB as db-postgres

  V->>CC: run in parallel on all nodes
  Note over CC: disable swap, load kernel modules,<br/>install containerd + kubetools,<br/>set kubelet node-ip

  V->>CP: run on cp1
  CP->>CP: kubeadm init --pod-network-cidr=10.244.0.0/16
  CP->>CP: apply Flannel CNI
  CP->>CP: patch Flannel --iface=enp0s8
  CP->>CP: helm install db-ingress-nginx db-argocd
  CP->>CP: kubectl apply k8s/ manifests
  CP->>CP: generate join.sh

  V->>W: run on workers
  W->>CP: poll nc 192.168.56.10:6443 until ready
  W->>CP: kubeadm join (via join.sh)

  Note over DB: pod schedules on worker
  DB->>DB: PostgreSQL ready

  Note over API: pod schedules on worker
  API->>DB: pg_isready polls every 2s
  API->>DB: alembic upgrade head (create table, seed data)
  API->>API: uvicorn starts on :8000
  API->>API: startup probe passes
  API->>API: readiness probe passes → added to service endpoints
"@

# 3. HTTP Request Flow
Get-DiagramPng "03_http_request_flow" @"
sequenceDiagram
  participant B as Browser
  participant CF as Cloudflare Edge
  participant T as db-cloudflared
  participant I as ingress-nginx
  participant F as db-frontend<br/>(Apache)
  participant A as db-api<br/>(FastAPI)
  participant DB as db-postgres

  B->>CF: GET https://project.beckersd.com/
  CF->>T: HTTP via outbound tunnel
  T->>I: HTTP forward
  I->>F: Host: project.beckersd.com  path: /
  F->>B: index.html

  Note over B: JavaScript executes

  B->>CF: fetch /api/name
  CF->>T: HTTP via tunnel
  T->>I: HTTP forward
  I->>A: path: /api → db-api:80 (round-robin)
  A->>DB: SELECT * FROM person LIMIT 1
  DB->>A: row {id:1, name:'Dieter Beckers'}
  A->>B: {"name":"Dieter Beckers"}

  B->>CF: fetch /api/container-id
  CF->>T: HTTP via tunnel
  T->>I: HTTP forward
  I->>A: path: /api → db-api:80 (may hit other replica)
  A->>B: {"container_id":"abc123","hostname":"worker2"}

  Note over B: Page renders greeting + container ID
"@

# 4. Name Update Flow
Get-DiagramPng "04_name_update_flow" @"
flowchart TD
  A["Operator on cp1"] --> B["source load_env_var.sh\nPrompts for DB_USER and DB_PASSWORD\nExports to current shell session"]
  B --> C["bash update_name.sh Alice"]
  C --> D["kubectl get pod -n db-stack\n-l app=db-postgres\nFinds: db-postgres-0"]
  D --> E["kubectl exec -i db-postgres-0\nenv PGPASSWORD=demo psql\nUPDATE person SET name='Alice' WHERE id=1"]
  E --> F["PostgreSQL confirms UPDATE 1"]
  F --> G["curl /api/name\nReturns: name=Alice"]
  G --> H["Browser refresh\nWelcome Alice!"]
"@

# 5. Auto Layout Refresh Flow
Get-DiagramPng "05_auto_refresh_flow" @"
flowchart TD
  A["Browser loads page\nwindow.currentVersion = null"] --> B["init: fetchName + fetchContainerId"]
  B --> C["checkVersion called immediately"]
  C --> D["fetch /version.txt?_t=timestamp\ncache-busting query string"]
  D --> E{"currentVersion matches?"}
  E -- "Yes (no change)" --> F["setInterval: wait 15 seconds"]
  F --> D
  E -- "No (version changed)" --> G["location.reload()\nFull page refresh"]
  G --> A

  H["Operator: edit version.txt\n1 to 2\nRebuild image\nkubectl rollout restart"] --> I["New pod serves version.txt = 2"]
  I --> E
"@

# 6. GitOps Sync Flow
Get-DiagramPng "06_gitops_sync_flow" @"
flowchart TD
  A["Developer edits manifest\nin k8s/ directory"] --> B["git commit + git push\nto main branch"]
  B --> C["GitHub\ndabeastnet/db-k8s-stack"]
  C --> D["ArgoCD repo-server\npolls every ~3 minutes"]
  D --> E{"Diff between\nGit HEAD and\ncluster state?"}
  E -- No --> D
  E -- Yes --> F["ArgoCD application-controller\ngenerates sync plan"]
  F --> G["kubectl apply changed manifests\nto db-stack namespace"]
  G --> H["Cluster state matches\nGit HEAD"]

  I["Manual kubectl edit\nin cluster"] --> J{"selfHeal: true\ndetects drift"}
  J --> F

  K["Resource deleted from Git\nautomated.prune: true"] --> F
"@

Write-Host "`nAll diagrams rendered to $diagDir"

# ── Rebuild HTML with embedded diagrams ────────────────────────────────────────
Write-Host "`nRebuilding HTML and DOCX with embedded diagrams..."
$htmlScript = "$PSScriptRoot\build_docx.ps1"

# We'll re-run build_docx.ps1 but first patch repository_documentation.md
# to replace the ASCII flow blocks with <img> references.
# Actually we patch the HTML file directly after generation.

# Step 1: regenerate HTML from MD
& powershell -ExecutionPolicy Bypass -File $htmlScript

# Step 2: read the HTML
$htmlFile   = "$base\repository_documentation.html"
$docxFile   = "$base\repository_documentation.docx"
$html       = Get-Content $htmlFile -Raw -Encoding UTF8

# Helper: embed PNG as base64 data URI
function Get-DataUri([string]$pngPath) {
    if (-not (Test-Path $pngPath)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($pngPath)
    $b64   = [Convert]::ToBase64String($bytes)
    return "data:image/png;base64,$b64"
}

# Map of section title (as it appears in the HTML <h3>) → diagram file
$replacements = @(
    @{
        Section = "5.1 Architecture Overview"
        DiagFile = "$diagDir\01_architecture.png"
        AsciiMark = "TLS termination for project.beckersd.com"
    },
    @{
        Section = "5.2 Application Start Sequence"
        DiagFile = "$diagDir\02_startup_sequence.png"
        AsciiMark = "provision-common.sh"
    },
    @{
        Section = "5.3 HTTP Request Flow"
        DiagFile = "$diagDir\03_http_request_flow.png"
        AsciiMark = "Browser: GET https"
    },
    @{
        Section = "5.4 Name Update Flow"
        DiagFile = "$diagDir\04_name_update_flow.png"
        AsciiMark = "Operator: source load_env_var"
    },
    @{
        Section = "5.5 Auto Layout Refresh Flow"
        DiagFile = "$diagDir\05_auto_refresh_flow.png"
        AsciiMark = "Browser tab has page open"
    },
    @{
        Section = "5.6 GitOps Sync Flow"
        DiagFile = "$diagDir\06_gitops_sync_flow.png"
        AsciiMark = "Developer: git push"
    }
)

# Replace each <pre> block that contains the ASCII flows with an <img> tag
# Strategy: find <pre> blocks containing the ascii marker and replace with img

foreach ($r in $replacements) {
    $uri = Get-DataUri $r.DiagFile
    if (-not $uri) { Write-Warning "Skipping $($r.DiagFile) - file not found"; continue }

    $escapedMarker = [regex]::Escape($r.AsciiMark)
    # Match <pre>...</pre> that contains the marker
    $pattern = '(?s)<pre>[^<]*' + $escapedMarker + '[^<]*(?:<[^/].*?)?</pre>'
    $imgTag  = "<div style='text-align:center;margin:12pt 0'><img src='$uri' style='max-width:100%;border:1px solid #ddd;padding:4px'/></div>"

    $newHtml = [regex]::Replace($html, $pattern, $imgTag)
    if ($newHtml -ne $html) {
        Write-Host "  Replaced ASCII flow for: $($r.AsciiMark)"
        $html = $newHtml
    } else {
        Write-Warning "  Pattern not matched for: $($r.AsciiMark)"
    }
}

[System.IO.File]::WriteAllText($htmlFile, $html, [System.Text.Encoding]::UTF8)
Write-Host "  HTML updated with embedded diagram images"

# Step 3: re-open in Word and save as DOCX
Write-Host "  Opening in Word and saving DOCX..."
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc  = $word.Documents.Open($htmlFile)
$doc.SaveAs([ref]$docxFile, [ref]16)
$doc.Close($false)
$word.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null

Write-Host "`nDone."
Write-Host "  DOCX : $docxFile"
Write-Host "  HTML : $htmlFile"
