# --- SELF-ELEVATION BLOCK ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList "-ExecutionPolicy Bypass $arguments"
    Break
}

$ErrorActionPreference = "SilentlyContinue"
$ScriptVersion = ".319"
$ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$UserName = $env:USERNAME
$Computer = $env:COMPUTERNAME

# --- DIRECTORY SETUP ---
$basePath = "C:\_LLMDiag"
if (-not (Test-Path $basePath)) { New-Item -ItemType Directory -Path $basePath | Out-Null }

# Session directory for this specific run
$counter = 1
do { $diagDir = Join-Path $basePath "LLMDiag$counter"; $counter++ } while (Test-Path $diagDir)
New-Item -ItemType Directory -Path $diagDir | Out-Null
Set-Location $diagDir

# --- SESSION LOGGING (Robust Init) ---
$sessionLog = Join-Path $diagDir "diag_session.log"
# Force creation and ensure it's not locked
"LLMDIAG Alpha Session Log`r`nVersion: $ScriptVersion`r`nStart: $ReportDate`r`n---" | Out-File $sessionLog -Force

function Write-Diag ($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    Add-Content -Path $sessionLog -Value "[$ts] $msg"
    Write-Host "   -> $msg" -ForegroundColor Gray
}
Write-Diag "Session directory established: $diagDir"

# Central Backup Directory (from Tweaker script)
$BackupBaseDir = Join-Path -Path $basePath -ChildPath "TweakBackups"
if (!(Test-Path $BackupBaseDir)) { New-Item -Path $BackupBaseDir -ItemType Directory | Out-Null }
$LogFile = Join-Path -Path $BackupBaseDir -ChildPath "TweakLog.txt"

# --- LOGGING & PRIVACY ---
function Write-TweakLog ($message, $isError = $false) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $type = if ($isError) { "[ERROR]" } else { "[INFO]" }
    "[$timestamp] [v$ScriptVersion] [$Computer\$UserName] $type $message" | Out-File -FilePath $LogFile -Append
}

function Sanitize-Text ($text) {
    if ($text) { return $text -replace [regex]::Escape($UserName), "[USER]" }
    return $text
}

# --- BACKUP LOGIC ---
function Get-NextBackupFolder {
    $i = 1
    while (Test-Path "$BackupBaseDir\bkp$i") { $i++ }
    return New-Item -Path "$BackupBaseDir\bkp$i" -ItemType Directory
}

# --- DIAGNOSTIC FUNCTIONS ---

function Check-HardwareOS {
    Write-Host "`n[1/5] Collecting System Foundation..." -ForegroundColor Cyan
    Write-Diag "Collecting System Hardware & OS data..."
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $disk = Get-PSDrive C | Select-Object Used, Free
    
    # Live Usage (System) - 5s Sampling for accuracy
    Write-Diag "Sampling CPU load (5s average)..."
    $cpuLoad = 0
    try {
        $samples = Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 5 -ErrorAction SilentlyContinue
        if ($samples) {
            $cpuLoad = ($samples | ForEach-Object { $_.CounterSamples[0].CookedValue } | Measure-Object -Average).Average
        } else {
            $cpuData = Get-CimInstance -ClassName Win32_Processor -Property LoadPercentage
            $cpuLoad = ($cpuData | Measure-Object -Property LoadPercentage -Average).Average
        }
    } catch { Write-Diag "CPU Load Query Failed: $($_.Exception.Message)" }
    if ($null -eq $cpuLoad) { $cpuLoad = 0 }
    
    $memFree = $os.FreePhysicalMemory / 1KB
    $memTotal = $os.TotalVisibleMemorySize / 1KB
    $memUsed = $memTotal - $memFree
    $memUsagePct = [math]::Round(($memUsed / $memTotal) * 100, 1)

    # VRAM Usage (System-wide) - Inclusive of all GPUs
    Write-Diag "Calculating total VRAM capacity across all adapters..."
    $vramTotalGB = 0
    $gpus = Get-CimInstance Win32_VideoController
    foreach ($g in $gpus) { 
        $ram = [double]$g.AdapterRAM
        
        # WMI AdapterRAM is a uint32, so it caps at 4GB or returns negative/large values for modern cards
        if ($ram -le 0 -or $ram -ge 4GB) { 
            # Attempt to get from Registry (more reliable for >4GB VRAM)
            try {
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
                $subKeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue
                foreach ($key in $subKeys) {
                    $val = Get-ItemProperty $key.PSPath -Name "HardwareInformation.MemorySize" -ErrorAction SilentlyContinue
                    $name = Get-ItemProperty $key.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue
                    if ($name.DriverDesc -eq $g.Name -and $val."HardwareInformation.MemorySize") {
                        $ram = [double]$val."HardwareInformation.MemorySize"
                        break
                    }
                }
            } catch {}
        }
        
        # Final fallback for known cards if Registry fails
        if ($ram -le 0 -or $ram -gt 100GB) {
            if ($g.Name -match "3060") { $ram = 12GB }
            elseif ($g.Name -match "3090|4090") { $ram = 24GB }
            else { $ram = 8GB }
        }

        $vramTotalGB += [math]::Round($ram / 1GB, 2) 
        Write-Diag "Found GPU: $($g.Name) ($([math]::Round($ram / 1GB, 2)) GB)"
    }
    
    # VRAM Usage (Live) - Summing all Dedicated usage counters
    Write-Diag "Sampling live VRAM usage..."
    $vramUsageGB = 0
    try {
        $vramCounters = Get-Counter "\GPU Adapter Memory(*)\Dedicated Usage" -ErrorAction SilentlyContinue
        if ($vramCounters) { 
            $totalBytes = 0
            foreach ($s in $vramCounters.CounterSamples) { $totalBytes += $s.CookedValue }
            $vramUsageGB = [math]::Round($totalBytes / 1GB, 2)
        }
    } catch { Write-Diag "VRAM Usage Counter Failed" }
    
    # LLM VRAM Footprint Audit
    $activeLLMs = Get-Process *studio*,*llama*,*ollama*,*server*,*main* -ErrorAction SilentlyContinue
    $llmFootprintGB = 0
    if ($activeLLMs) {
        Write-Diag "Auditing LLM process VRAM footprint..."
        try {
            $procCounters = Get-Counter "\GPU Process Memory(*)\Local Usage" -ErrorAction SilentlyContinue
            if ($procCounters) {
                $pBytes = 0
                foreach ($s in $procCounters.CounterSamples) { $pBytes += $s.CookedValue }
                $llmFootprintGB = [math]::Round($pBytes / 1GB, 2)
                Write-Diag "LLM processes are holding $llmFootprintGB GB of VRAM."
                if ($llmFootprintGB -gt $vramUsageGB) { $vramUsageGB = $llmFootprintGB }
            }
        } catch { Write-Diag "Process VRAM audit failed" }
    }

    $vramUsagePct = if ($vramTotalGB -gt 0) { [math]::Round(($vramUsageGB / $vramTotalGB) * 100, 1) } else { 0 }
    
    # Store footprint for bottleneck analysis
    $llmFootprintGB | Out-File "llm_footprint.txt"

    # CPU Instruction Set Detection
    $cpuFeatures = @()
    $cpuInfo = (Get-CimInstance Win32_Processor).Caption + " " + (Get-CimInstance Win32_Processor).Name
    if ($cpuInfo -match "AVX2") { $cpuFeatures += "AVX2" }
    if ($cpuInfo -match "AVX512") { $cpuFeatures += "AVX512" }
    if ($cpuFeatures.Count -eq 0) { $cpuFeatures += "Standard (AVX/SSE)" }

    # Pagefile Check
    $pagefile = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
    $pfStatus = "Dynamic/System Managed"
    $pfRecommendation = ""
    if ($pagefile) {
        $pfSize = [math]::Round($pagefile.MaximumSize, 0)
        if ($pagefile.InitialSize -eq $pagefile.MaximumSize) {
            $pfStatus = "Fixed ($($pfSize) MB)"
            if ($pfSize -ne 8192) { $pfRecommendation = "[STABILITY] Recommendation: Pagefile is fixed but not at 8192MB." }
        } else {
            $pfStatus = "Dynamic ($($pfSize) MB)"
            $pfRecommendation = "[STABILITY] Recommendation: Pagefile is dynamic. Set to Fixed 8192MB to prevent allocation stutters."
        }
    } else {
        $pfRecommendation = "[STABILITY] Recommendation: System Managed Pagefile detected. Set to Fixed 8192MB for LLM stability."
    }

    $diskTotal = ($disk.Used + $disk.Free) / 1GB
    $diskUsed = $disk.Used / 1GB
    $diskPct = [math]::Round(($diskUsed / $diskTotal) * 100, 1)

    $hwLog = @()
    $hwLog += "OS: $($os.Caption) (Build $($os.BuildNumber))"
    $hwLog += "CPU: $($cpu.Name) ($($cpu.NumberOfCores) Cores / $($cpu.NumberOfLogicalProcessors) Threads)"
    $hwLog += "CPU Instructions: $($cpuFeatures -join ', ')"
    $hwLog += "METRIC_CPU: $([math]::Round($cpuLoad, 1))% Used / 100% Total ($cpuLoad% Active)"
    $hwLog += "METRIC_RAM: $([math]::Round($memUsed / 1024, 2)) GB Used / $([math]::Round($memTotal / 1024, 2)) GB Total ($memUsagePct% Active)"
    $hwLog += "METRIC_VRAM: $($vramUsageGB) GB Used / $($vramTotalGB) GB Total ($vramUsagePct% Active)"
    $hwLog += "METRIC_DISK: $([math]::Round($diskUsed, 2)) GB Used / $([math]::Round($diskTotal, 2)) GB Total ($diskPct% Active)"
    $hwLog += "Pagefile: $pfStatus"
    if ($pfRecommendation) { $hwLog += $pfRecommendation }
    
    $hwLog | Out-File "hardware_os.txt"
    Write-Diag "System data collected."
    Write-Host "Done." -ForegroundColor Green
}

function Check-GPUCompute {
    Write-Host "`n[2/5] Checking GPU & Compute Layers (ROCm/Vulkan)..." -ForegroundColor Cyan
    Write-Diag "Checking GPU hardware and PCIe link states..."
    $gpus = Get-CimInstance Win32_VideoController
    
    # Driver Flavor Detection & LUID Mapping
    $gpuLog = @()
    $luidMap = @{}
    foreach ($gpu in $gpus) {
        $vendor = "Unknown"
        if ($gpu.Name -match "NVIDIA") { $vendor = "NVIDIA" }
        elseif ($gpu.Name -match "AMD|Radeon") { $vendor = "AMD" }
        
        $flavor = if ($vendor -eq "AMD") { "Standard/Adrenalin" } else { "NVIDIA Driver" }
        if ($gpu.Caption -match "PRO" -or $gpu.Name -match "PRO") { $flavor = "$vendor PRO Edition" }
        
        $type = "Dedicated"
        if ($gpu.Name -match "Graphics" -or $gpu.Caption -match "Radeon.*Graphics") { $type = "iGPU" }
        
        $gpuLog += "Name: $($gpu.Name) [$type]"
        $gpuLog += "Vendor: $vendor"
        $gpuLog += "Driver: $($gpu.DriverVersion) ($flavor)"
        $gpuLog += "Status: $($gpu.Status)"
        
        # PCIe Link State
        try {
            $pnp = Get-PnpDevice -FriendlyName "*$($gpu.Name)*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pnp) {
                # Extract LUID
                if ($gpu.PNPDeviceID -and $gpu.PNPDeviceID.Contains('\')) {
                    $luid = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*" | Where-Object { $_.MatchingDeviceId -match $gpu.PNPDeviceID.Split('\')[1] }).NetLuidIndex
                    if ($luid) { $luidMap[$luid] = $gpu.Name }
                }

                $speed = Get-PnpDeviceProperty -InstanceId $pnp.InstanceId -KeyName "DEVPKEY_PciDevice_CurrentLinkSpeed" -ErrorAction SilentlyContinue
                $width = Get-PnpDeviceProperty -InstanceId $pnp.InstanceId -KeyName "DEVPKEY_PciDevice_CurrentLinkWidth" -ErrorAction SilentlyContinue
                
                if ($speed.Data) {
                    $gen = switch ($speed.Data) {
                        1 { "Gen 1 (2.5 GT/s)" }
                        2 { "Gen 2 (5.0 GT/s)" }
                        3 { "Gen 3 (8.0 GT/s)" }
                        4 { "Gen 4 (16.0 GT/s)" }
                        5 { "Gen 5 (32.0 GT/s)" }
                        default { "Unknown ($($speed.Data))" }
                    }
                    $gpuLog += "PCIe Link: x$($width.Data) @ $gen"
                }
            }
        } catch {}
        $gpuLog += "---"
    }
    $gpuLog | Out-File "GPU.txt"
    
    # Vulkan Detection
    $vulkanLog = @()
    Write-Diag "Checking Vulkan runtime..."
    if (Test-Path "C:\Windows\System32\vulkan-1.dll") {
        $vulkanLog += "[+] Vulkan Runtime: Detected (vulkan-1.dll)"
        if (Get-Command vulkaninfo -ErrorAction SilentlyContinue) {
            Write-Diag "Capturing Vulkan summary..."
            $vSummary = vulkaninfo --summary 2>&1 | Out-String
            $vulkanLog += $vSummary
            $vCount = ($vSummary | Select-String "Device Name" -AllMatches).Matches.Count
            $vulkanLog += "[+] Vulkan Devices Found: $vCount"
            
            # Enhanced Extension Check
            Write-Diag "Checking Vulkan AI Extensions..."
            $vFull = vulkaninfo 2>&1 | Out-String
            $vulkanLog += "--- Vulkan AI Extensions ---"
            $exts = @("VK_KHR_shader_float16_int8", "VK_KHR_variable_pointers", "shaderInt8", "shaderInt16")
            foreach ($ext in $exts) {
                if ($vFull -match $ext) { $vulkanLog += "[+] $ext: Supported" }
                else { $vulkanLog += "[-] $ext: Not found" }
            }
            if ($vFull -match "variablePointers") { $vulkanLog += "[+] variablePointers: Supported" }
        } else {
            $vulkanLog += "[!] vulkaninfo not found in PATH. Summary unavailable."
        }
    } else {
        $vulkanLog += "[-] Vulkan Runtime: Not found in System32."
    }
    $vulkanLog | Out-File "vulkan_info.txt"
    
    # VRAM Breakdown (Dedicated vs Shared)
    $vramLog = @()
    try {
        $counters = Get-Counter "\GPU Adapter Memory(*)\Dedicated Usage", "\GPU Adapter Memory(*)\Shared Usage" -ErrorAction SilentlyContinue
        foreach ($sample in $counters.CounterSamples) {
            $val = [math]::Round($sample.CookedValue / 1MB, 2)
            # Try to resolve LUID to Name
            $label = $sample.InstanceName
            if ($luidMap.Count -gt 0) {
                foreach ($key in $luidMap.Keys) {
                    if ($key -and ($label -match "0x[0-9a-fA-F]+_0x0*$([Convert]::ToString($key, 16))")) {
                        $label = $luidMap[$key]
                        break
                    }
                }
            }
            $vramLog += "$label [$($sample.Path.Split('\')[-1])]: $val MB"
        }
    } catch { $vramLog += "Performance counters for VRAM not available." }
    $vramLog | Out-File "vram_telemetry.txt"

    # Live Clock Telemetry (New Module v2.9.0)
    $clockLog = @()
    $smiPath = Get-Command rocm-smi -ErrorAction SilentlyContinue
    if (-not $smiPath) { $smiPath = Get-ChildItem "C:\Program Files\AMD\ROCm\*\bin\rocm-smi.exe" | Select-Object -ExpandProperty FullName -First 1 }
    
    if ($smiPath) {
        $clockLog += "--- Active Clocks (ROCm-SMI) ---"
        $clockLog += & $smiPath --showclock --showmemclock 2>&1 | Out-String
    } else {
        $clockLog += "[!] rocm-smi not found. Clocks unavailable via SMI."
    }
    $clockLog | Out-File "clocks.txt"

    $vramTotal = 0
    if (Get-Command hipinfo -ErrorAction SilentlyContinue) { 
        $hip = hipinfo
        $hip | Out-File "hipinfo.txt"
        $vramMatches = [regex]::Matches($hip, 'totalGlobalMem:\s+([\d\.]+)\s+GB')
        foreach ($match in $vramMatches) { $vramTotal += [double]$match.Groups[1].Value }
    } else { "HIP not found" | Out-File "hipinfo.txt" }
    
    "Total Addressable VRAM: $vramTotal GB" | Out-File "vram_map.txt"
    Write-Host "Done." -ForegroundColor Green
}

function Check-RuntimesEnv {
    Write-Host "`n[3/5] Checking Runtimes & Environment..." -ForegroundColor Cyan
    Write-Diag "Auditing environment variables and system PATH..."
    $envVars = Get-ChildItem Env: | Where-Object { $_.Name -match "HIP|ROCR|GPU|CUDA|HSA|AMD|PATH" }
    $envVars | Select-Object Name, Value | Out-File "environment.txt"
    $env:PATH -split ";" | Out-File "path.txt"
    
    $hsaLog = @()
    if ($env:HSA_OVERRIDE_GFX_VERSION) {
        $hsaLog += "[!] HSA_OVERRIDE_GFX_VERSION is set to: $($env:HSA_OVERRIDE_GFX_VERSION)"
    } else {
        $hsaLog += "[+] No HSA Override set (Standard Best Practice for Native Windows)."
    }

    if ($env:HIP_VISIBLE_DEVICES) {
        $hsaLog += "[!] HIP_VISIBLE_DEVICES is set to: $($env:HIP_VISIBLE_DEVICES)"
        $hsaLog += "    WARNING: This restricts which GPUs the LLM runner can see."
    }
    
    if ($env:AMD_SERIALIZE_KERNEL) {
        $hsaLog += "[!] AMD_SERIALIZE_KERNEL is set to: $($env:AMD_SERIALIZE_KERNEL)"
        $hsaLog += "    CONTEXT: Usually used for debugging driver crashes."
    }

    $hsaLog | Out-File "hsa_notes.txt"
    Write-Host "Done." -ForegroundColor Green
}

function Check-Runners {
    Write-Host "`n[4/5] Detecting LLM Runtimes & Ports Used..." -ForegroundColor Cyan
    Write-Diag "Scanning for active LLM processes and port listeners..."
    $runnerLog = @()
    $pidToName = @{}
    
    # Expanded process list to catch LM Studio and others
    $procPatterns = @("*ollama*", "*anythingllm*", "*koboldcpp*", "*lmstudio*", "*lm-studio*", "*studio*", "*llama*", "*server*", "*main*", "*gpt4all*", "*node*")
    $active = Get-Process $procPatterns -ErrorAction SilentlyContinue
    if ($active) { 
        foreach ($p in $active) { 
            $pName = $p.ProcessName
            # LM Studio often runs via node/electron, check FileDescription
            try { 
                $desc = $p.MainModule.FileVersionInfo.FileDescription
                if ($desc -and $desc -match "LM Studio|AnythingLLM|Ollama|Kobold") { $pName = $desc }
            } catch {}
            
            if ($p.ProcessName -match "node" -and $pName -eq "node") { continue } # Skip generic node if no desc
            
            $runnerLog += "[+] ACTIVE: $pName (PID: $($p.Id))" 
            $pidToName[$p.Id] = $pName
        } 
    }
    else { $runnerLog += "[!] No active LLM runner processes detected via process name scan." }

    # Port Usage Check (Filtering for LISTENING state to avoid false conflict flags)
    $ports = @(11434, 1234, 5001, 8080)
    foreach ($port in $ports) {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conns) {
            $pids = $conns.OwningProcess | Select-Object -Unique
            $procNames = @()
            foreach ($pid in $pids) {
                $pName = ""
                # Check our pre-scanned map first
                if ($pidToName.ContainsKey($pid)) { $pName = $pidToName[$pid] }
                
                if (-not $pName) {
                    $p = Get-Process -Id $pid -ErrorAction SilentlyContinue
                    if ($p) { 
                        $pName = $p.ProcessName
                        try { if ($p.MainModule.FileVersionInfo.FileDescription) { $pName = $p.MainModule.FileVersionInfo.FileDescription } } catch {}
                    } else {
                        # Fallback to WMI for processes that might be tricky to catch with Get-Process
                        $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $pid" -ErrorAction SilentlyContinue
                        if ($wmiProc) { $pName = $wmiProc.Name }
                    }
                }
                
                if ($pName) { $procNames += "$pName (PID: $pid)" }
                else { $procNames += "Unknown Process (PID: $pid)" }
            }
            
            $status = if ($pids.Count -gt 1) { "PORT CONFLICT" } else { "PORT IN USE" }
            $displayNames = if ($procNames.Count -gt 0) { $procNames -join ', ' } else { "Unknown Process (PID: $($pids -join ','))" }
            $runnerLog += "[!] ${status}: Port $port is used by $displayNames"
            
            # Conditional Latency Test for KoboldCPP (5001)
            if ($port -eq 5001) {
                Write-Host "   -> Port 5001 Active. Testing KoboldCPP Latency..." -ForegroundColor Gray
                $start = Get-Date
                try {
                    $test = Invoke-RestMethod -Uri "http://localhost:5001/api/v1/model" -Method Get -TimeoutSec 2 -ErrorAction Stop
                    $end = Get-Date
                    $latency = [math]::Round(($end - $start).TotalMilliseconds, 0)
                    $runnerLog += "[+] KoboldCPP Latency: $($latency)ms (API Response)"
                } catch {
                    $runnerLog += "[!] KoboldCPP: Port open but API not responding."
                }
            }
        } elseif ($port -eq 5001) {
            $runnerLog += "[+] KoboldCPP: Offline"
        }
    }

    if (Get-Command python -ErrorAction SilentlyContinue) { $runnerLog += "Python: $((python --version 2>&1 | Out-String).Trim())" }
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        if (docker ps --format "{{.Names}}" | Select-String "anythingllm") { $runnerLog += "[+] Docker: AnythingLLM Container is UP" }
    }
    $runnerLog | Out-File "runners.txt"
    Write-Host "Done." -ForegroundColor Green
}

function Get-TweakStatus {
    $sysLog = @()
    
    # 1. HPET
    $bcd = bcdedit /enum | Out-String
    if ($bcd -match "useplatformclock\s+Yes") { 
        $sysLog += "[-] HPET: ENABLED (Slow/Timer Jitter)" 
        $hpetColor = "Red"
    } else { 
        $sysLog += "[+] HPET: DISABLED (Fast/Optimized)" 
        $hpetColor = "Green"
    }
    
    # 2. VBS
    $vbs = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue
    if ($vbs.VirtualizationBasedSecurityStatus -eq 2) { 
        $sysLog += "[!] VBS: ENABLED (Slow/Security Active) (required for virtualization)" 
        $vbsColor = "Yellow"
    } else { 
        $sysLog += "[+] VBS: DISABLED (Fast/Raw Compute)" 
        $vbsColor = "Green"
    }

    # 3. Network Throttling
    $netPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    $netVal = Get-ItemProperty -Path $netPath -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
    $val = $netVal.NetworkThrottlingIndex
    if ($val -eq -1 -or $val -eq 4294967295) { 
        $sysLog += "[+] Network Throttling: DISABLED (Fast)" 
        $netColor = "Green"
    } else { 
        $sysLog += "[-] Network Throttling: ENABLED (Slow)" 
        $netColor = "Red"
    }

    # 4. Power Plan
    $activePlan = powercfg /getactivescheme
    if ($activePlan -match "Ultimate|High") { 
        $sysLog += "[+] Power Plan: Optimized (Fast)" 
        $pwrColor = "Green"
    } else { 
        $sysLog += "[-] Power Plan: Standard (Slow)" 
        $pwrColor = "Red"
    }

    return @{ HPET = $hpetColor; VBS = $vbsColor; Net = $netColor; Pwr = $pwrColor; Log = $sysLog }
}

function Check-WindowsSystem {
    Write-Host "`n[5/5] Checking Windows System Performance..." -ForegroundColor Cyan
    Write-Diag "Evaluating Windows-specific optimizations (HPET, VBS, Power)..."
    $status = Get-TweakStatus
    $sysLog = $status.Log

    # WSL2 Audit
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $wslList = wsl --list --verbose 2>$null
        if ($wslList) { $sysLog += "[+] WSL2: Detected (Active Distros found)" }
        else { $sysLog += "[!] WSL2: Installed but no distros found" }
    } else {
        $sysLog += "[!] WSL2: Not detected (Recommended for advanced ROCm/Docker setups)"
    }

    # Virtualization Check
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.DataExecutionPrevention_Available) { $sysLog += "[+] Hardware Virtualization: Enabled in BIOS" }
    else { $sysLog += "[-] Hardware Virtualization: Disabled (Breaks WSL2/Docker)" }

    $sysLog | Out-File "windows_system.txt"
    Write-Host "Done." -ForegroundColor Green
}

function Show-TweakBriefing ($id) {
    Clear-Host
    switch ($id) {
        "1" {
            Write-Host "--- TWEAK: Disable HPET (Timer Jitter) ---" -ForegroundColor Cyan
            Write-Host "BENEFIT: Reduces 'timer jitter'. Improves LLM inference consistency."
            Write-Host "ACTION: Removes 'useplatformclock' from BCD."
        }
        "2" {
            Write-Host "--- TWEAK: Ultimate Power Plan ---" -ForegroundColor Cyan
            Write-Host "BENEFIT: Eliminates micro-latency from CPU core parking during heavy compute."
            Write-Host "ACTION: Unlocks and activates the 'Ultimate Performance' profile."
        }
        "3" {
            Write-Host "--- TWEAK: Network & Responsiveness ---" -ForegroundColor Cyan
            Write-Host "BENEFIT: Prevents network packet throttling during high CPU usage (common in LLM servers)."
            Write-Host "ACTION: Sets SystemResponsiveness to 0 and ThrottlingIndex to -1."
        }
    }
}

# --- TUNING SUB-MENU ---

function Show-TuningMenu {
    while ($true) {
        Clear-Host
        $status = Get-TweakStatus
        Write-Host "=== Change System Performance (Sub-Menu) ===" -ForegroundColor Yellow
        Write-Host "Current Status:"
        Write-Host " - HPET: " -NoNewline; Write-Host $status.Log[0].Substring(10) -ForegroundColor $status.HPET
        Write-Host " - VBS:  " -NoNewline; Write-Host $status.Log[1].Substring(10) -ForegroundColor $status.VBS
        Write-Host " - Net:  " -NoNewline; Write-Host $status.Log[2].Substring(10) -ForegroundColor $status.Net
        Write-Host " - Pwr:  " -NoNewline; Write-Host $status.Log[3].Substring(10) -ForegroundColor $status.Pwr
        Write-Host ""
        Write-Host "1. Disable HPET"
        Write-Host "2. Enable Ultimate Power Plan"
        Write-Host "3. Network & System Responsiveness"
        Write-Host "4. Global Backup (Registry, BCD, Power)"
        Write-Host "R. RESTORE (Uses most recent backup folder)"
        Write-Host "B. Open Backup Directory"
        Write-Host "M. Back to Main Menu"
        
        $choice = Read-Host "`nEnter selection"
        if ($choice -eq "m") { return }
        if ($choice -eq "b") { explorer $BackupBaseDir; continue }

        if ($choice -eq "4") {
            $CurrentBkpDir = Get-NextBackupFolder
            Write-Host "Creating Global Backup in $($CurrentBkpDir.Name)..." -ForegroundColor Yellow
            try {
                reg export "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "$($CurrentBkpDir.FullName)\Registry_Initial.reg" /y | Out-Null
                bcdedit /export "$($CurrentBkpDir.FullName)\BCD_Initial.config" | Out-Null
                powercfg /getactivescheme | Out-File "$($CurrentBkpDir.FullName)\PowerPlan_Initial.txt"
                Write-TweakLog "Global Backup Created in $($CurrentBkpDir.Name)"
                Write-Host "Backups saved to $($CurrentBkpDir.FullName)" -ForegroundColor Green
            } catch {
                Write-TweakLog "Backup Failed: $($_.Exception.Message)" -isError $true
                Write-Host "Backup failed. Check log." -ForegroundColor Red
            }
            Pause; continue
        }

        if ($choice -eq "r") {
            $dirs = Get-ChildItem -Path $BackupBaseDir -Directory -Filter "bkp*" | Sort-Object LastWriteTime -Descending
            if ($dirs.Count -eq 0) { Write-Host "No backup folders found!" -ForegroundColor Red; Start-Sleep 2; continue }
            $latest = $dirs[0]
            
            Write-Host "`n--- RESTORING FROM $($latest.Name) ---" -ForegroundColor Yellow
            try {
                if (Test-Path "$($latest.FullName)\Registry_Initial.reg") { reg import "$($latest.FullName)\Registry_Initial.reg" }
                bcdedit /set useplatformclock Yes 2>$null
                if (Test-Path "$($latest.FullName)\PowerPlan_Initial.txt") {
                    $oldPlan = Get-Content "$($latest.FullName)\PowerPlan_Initial.txt" | Select-String -Pattern "[0-9a-fA-F-]{36}"
                    if ($oldPlan) { powercfg /setactive $oldPlan.Matches.Value }
                }
                Write-TweakLog "Restored from $($latest.Name)"
                Write-Host "Restoration complete." -ForegroundColor Green
            } catch { Write-TweakLog "Restore Failed: $($_.Exception.Message)" -isError $true }
            Pause; continue
        }

        if ("1","2","3" -contains $choice) {
            Show-TweakBriefing $choice
            Write-Host "`nWARNING: You are about to modify system settings." -ForegroundColor Yellow
            $confirm = Read-Host "Are you sure you want to proceed? (Y/N)"
            if ($confirm -ne "y") { continue }

            try {
                switch ($choice) {
                    "1" { bcdedit /deletevalue useplatformclock 2>$null; Write-TweakLog "Applied: Disable HPET" }
                    "2" { 
                        powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
                        $ultimateLine = (powercfg /list) | Select-String "Ultimate Performance" | Select-Object -First 1
                        $guid = ([regex]::Match($ultimateLine, '[0-9a-fA-F-]{36}')).Value
                        powercfg /setactive $guid
                        Write-TweakLog "Applied: Ultimate Power ($guid)"
                    }
                    "3" {
                        $sysPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                        Set-ItemProperty -Path $sysPath -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
                        Set-ItemProperty -Path $sysPath -Name "NetworkThrottlingIndex" -Value ([int32]-1) -Type DWord -Force
                        Write-TweakLog "Applied: Network Tweaks"
                    }
                }
                Write-Host "Tweak Applied Successfully." -ForegroundColor Green
            } catch { Write-TweakLog "Choice $choice Failed: $($_.Exception.Message)" -isError $true }
            Pause
        }
    }
}

# --- REPORT GENERATION ---

function Check-Telemetry {
    # Check VRAM usage before proceeding
    $vramUsageGB = 0
    try {
        $vramCounters = Get-Counter "\GPU Adapter Memory(*)\Dedicated Usage" -ErrorAction SilentlyContinue
        if ($vramCounters) { 
            $totalBytes = 0
            foreach ($s in $vramCounters.CounterSamples) { $totalBytes += $s.CookedValue }
            $vramUsageGB = [math]::Round($totalBytes / 1GB, 2)
        }
    } catch {}

    if ($vramUsageGB -lt 5) {
        Write-Host "`n[!] Low VRAM usage detected ($vramUsageGB GB)." -ForegroundColor Yellow
        Write-Host "Live Telemetry is most useful when a model is loaded." -ForegroundColor Gray
        $choice = Read-Host "Would you like to load a model now for better telemetry? (Y/N)"
        if ($choice -eq "y") {
            Write-Host "Please load your model in LM Studio/Ollama/etc. and press any key to continue..." -ForegroundColor Cyan
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }

    Write-Host "`n[6/6] Capturing Live Telemetry (10s Sample)..." -ForegroundColor Cyan
    Write-Diag "Starting 10s telemetry sampling loop..."
    Write-Host "TIP: Run an LLM inference NOW to capture data under load." -ForegroundColor Gray
    
    $telemetryLog = @()
    $smiPath = Get-Command rocm-smi -ErrorAction SilentlyContinue
    if (-not $smiPath) {
        $smiPath = Get-ChildItem "C:\Program Files\AMD\ROCm\*\bin\rocm-smi.exe" | Select-Object -ExpandProperty FullName -First 1
    }

    if ($smiPath) {
        $telemetryLog += "--- ROCM-SMI Output (Live) ---"
        for ($i=1; $i -le 5; $i++) {
            $telemetryLog += "Sample $i/5:"
            $telemetryLog += & $smiPath --showclock --showmemclock 2>&1 | Out-String
            Start-Sleep -Seconds 2
        }
    } else {
        $telemetryLog += "[!] rocm-smi not found in PATH or ROCm folders."
        $telemetryLog += "Attempting Windows Performance Counters (GPU Engine)..."
        try {
            $counters = Get-Counter "\GPU Adapter Memory(*)\Dedicated Usage", "\GPU Adapter Memory(*)\Shared Usage" -SampleInterval 2 -MaxSamples 3
            foreach ($c in $counters) {
                foreach ($s in $c.CounterSamples) {
                    $telemetryLog += "$($s.Path): $([math]::Round($s.CookedValue / 1MB, 2)) MB"
                }
            }
        } catch { $telemetryLog += "Telemetry capture failed." }
    }
    
    $telemetryLog | Out-File "telemetry_live.txt"
    Write-Host "Done." -ForegroundColor Green
}

function Generate-HTML {
    Write-Host "`nGenerating Sanitized HTML Report..." -ForegroundColor Cyan
    Write-Diag "Assembling HTML report..."
    $sections = @{
        "Foundation" = Get-Content "hardware_os.txt" -Raw
        "Windows"    = Get-Content "windows_system.txt" -Raw
        "Compute"    = (Get-Content "GPU.txt" -Raw) + "`n" + (Get-Content "vram_map.txt" -Raw)
        "Vulkan"     = Get-Content "vulkan_info.txt" -Raw
        "VRAM_Tele"  = Get-Content "vram_telemetry.txt" -Raw
        "Clocks"     = Get-Content "clocks.txt" -Raw
        "Telemetry"  = Get-Content "telemetry_live.txt" -Raw
        "HIP"        = Get-Content "hipinfo.txt" -Raw
        "Runtimes"   = (Get-Content "runners.txt" -Raw) + "`n" + (Get-Content "hsa_notes.txt" -Raw)
        "Env"        = Get-Content "environment.txt" -Raw
        "Path"       = (Get-Content "path.txt") -join "`n"
        "Footprint"  = Get-Content "llm_footprint.txt" -Raw
    }

    # Parse metrics for System section
    $cpuMetric = if ($sections.Foundation -match "METRIC_CPU: (.*)") { $matches[1] } else { "N/A" }
    $ramMetric = if ($sections.Foundation -match "METRIC_RAM: (.*)") { $matches[1] } else { "N/A" }
    $vramMetric = if ($sections.Foundation -match "METRIC_VRAM: (.*)") { $matches[1] } else { "N/A" }
    $diskMetric = if ($sections.Foundation -match "METRIC_DISK: (.*)") { $matches[1] } else { "N/A" }
    
    # Clean up Foundation text for display
    $foundationClean = $sections.Foundation -replace "METRIC_.*`r?`n", ""

    # --- BOTTLENECK ANALYSIS LOGIC ---
    $bottlenecks = @()
    $isIdle = $sections.Runtimes -match "No active LLM runner processes detected"
    
    # Extract VRAM stats for analysis
    $vramMatches = [regex]::Matches($sections.VRAM_Tele, '(?mi)^(.*) \[dedicated usage\]: ([\d\.]+) MB')
    $sharedMatches = [regex]::Matches($sections.VRAM_Tele, '(?mi)^(.*) \[shared usage\]: ([\d\.]+) MB')
    $totalVramGB = 0
    if ($sections.Compute -match "Total Addressable VRAM: ([\d\.]+) GB") { $totalVramGB = [double]$matches[1] }
    $totalVramMB = $totalVramGB * 1024
    
    # LLM Footprint Check
    $footprintGB = [double]$sections.Footprint
    if ($footprintGB -gt 0) {
        $vramBuffer = 0.5 # 500MB buffer for OS/Display
        if ($footprintGB -gt ($totalVramGB - $vramBuffer)) {
            $bottlenecks += "<span class='red'>[CRITICAL] VRAM Insufficiency: Active LLM processes require $($footprintGB)GB, but total Dedicated VRAM is only $($totalVramGB)GB. This forces data into slow Shared System Memory.</span>"
        } elseif ($footprintGB -gt ($totalVramGB * 0.9)) {
            $bottlenecks += "<span class='yellow'>[WARNING] Near VRAM Limit: LLM footprint ($($footprintGB)GB) is approaching total dedicated capacity ($($totalVramGB)GB). Stuttering may occur.</span>"
        }
    }

    # 1. Shared Memory Spillover
    foreach ($m in $sharedMatches) {
        $gpuName = $m.Groups[1].Value
        $usage = [double]$m.Groups[2].Value
        # Skip known iGPUs/APUs and unmapped LUIDs (which are usually the APU on these systems)
        if ($gpuName -match "Graphics" -or $gpuName -match "iGPU" -or $gpuName -match "luid_") { continue }
        if ($usage -gt 250) {
            $bottlenecks += "<span class='red'>[CRITICAL] VRAM Overflow ($gpuName): Shared System Memory usage detected ($usage MB). This will cause massive token latency.</span>"
        } elseif ($usage -gt 100) {
            $bottlenecks += "<span class='yellow'>[WARNING] VRAM Spillover ($gpuName): Shared System Memory usage detected ($usage MB). Performance may be degraded.</span>"
        }
    }

    # 2. VRAM Usage & Availability
    $maxDedicated = 0
    foreach ($m in $vramMatches) { if ([double]$m.Groups[2].Value -gt $maxDedicated) { $maxDedicated = [double]$m.Groups[2].Value } }
    
    if ($totalVramMB -gt 0) {
        $usagePct = ($maxDedicated / $totalVramMB) * 100
        $availableMB = $totalVramMB - $maxDedicated
        
        if ($availableMB -lt 5120) { # Less than 5GB available
            $bottlenecks += "<span class='yellow'>[POTENTIAL] Low VRAM Availability: Less than 5GB of VRAM is currently free ($([math]::Round($availableMB/1024, 1)) GB). Loading large models may fail or trigger spillover.</span>"
        }
        
        if ($usagePct -gt 70) {
            $bottlenecks += "<span class='red'>[ISSUE] High VRAM Usage: GPU is using $([math]::Round($usagePct, 1))% of VRAM. Close other apps to free up space for LLM weights.</span>"
        }
    }

    # 3. Pagefile Validation
    if ($sections.Foundation -match "\[STABILITY\] Recommendation: (.*)") {
        $bottlenecks += "<span class='yellow'>$($matches[0])</span>"
    }

    # 4. Vulkan Feature Table
    $vulkanTable = ""
    if ($sections.Vulkan -match "Vulkan Devices Found: (\d+)") {
        $vulkanTable = "<div class='box'><div class='box-header'>Vulkan AI Feature Support (INT4/8/16)</div><div class='box-content'><table style='width:100%; border-collapse: collapse;'>"
        $vulkanTable += "<tr style='background:#eee;'><th>Device</th><th>INT4</th><th>INT8</th><th>INT16</th></tr>"
        
        $gpuNames = @()
        $gpuMatches = [regex]::Matches($sections.Compute, 'Name: (.*) \[')
        foreach ($gm in $gpuMatches) { $gpuNames += $gm.Groups[1].Value }
        
        foreach ($gn in $gpuNames) {
            $i8 = if ($sections.Vulkan -match "shaderInt8: Supported") { "<span class='green'>✔</span>" } else { "<span class='red'>✘</span>" }
            $i16 = if ($sections.Vulkan -match "shaderInt16: Supported") { "<span class='green'>✔</span>" } else { "<span class='red'>✘</span>" }
            $i4 = if ($sections.Vulkan -match "NVIDIA|3060|3090|4090") { "<span class='green'>✔</span>" } else { "<span class='red'>✘</span>" } # Heuristic for Tensor Cores
            $vulkanTable += "<tr><td>$gn</td><td style='text-align:center;'>$i4</td><td style='text-align:center;'>$i8</td><td style='text-align:center;'>$i16</td></tr>"
        }
        $vulkanTable += "</table>"
        
        $varPtr = "yellow"
        $ptrStatus = "Unknown"
        if ($sections.Vulkan -match "VK_KHR_variable_pointers: Supported") { $varPtr = "green"; $ptrStatus = "Supported" }
        elseif ($sections.Vulkan -match "VK_KHR_variable_pointers: Not found") { $varPtr = "red"; $ptrStatus = "Not Supported" }
        
        $vulkanTable += "<p style='margin-top:10px;'>VK_KHR_variable_pointers: <span class='$varPtr'>$ptrStatus</span><br>"
        $vulkanTable += "<small>Allows the AI to handle dynamic memory addresses, which is vital for complex model architectures.</small></p></div></div>"
    }

    if ($sections.Compute -match "PCIe Link: x[1-4] @") { $bottlenecks += "<span class='yellow'>[WARNING] PCIe Bandwidth: GPU is running at x4 or lower. Prompt processing (TTFT) will be slow.</span>" }
    if ($sections.Runtimes -match "PORT CONFLICT") { $bottlenecks += "<span class='yellow'>[POTENTIAL] Resource Competition: Multiple LLM runners detected on the same port. Ensure they are not active simultaneously.</span>" }
    
    if ($sections.HIP -match "HIP not found") { $bottlenecks += "<span class='red'>[CRITICAL] AMD HIP SDK Missing: No ROCm/HIP layer detected. Local LLMs will likely run on CPU (Slow).</span>" }
    
    $bottleneckHtml = if ($bottlenecks.Count -eq 0) { "<span class='green'>[OK] No major bottlenecks detected in current state.</span>" }
    else { $bottlenecks -join "`n" }

    $htmlBody = @"
<!DOCTYPE html><html><head><title>LLM Diag v$ScriptVersion</title>
<style>
    body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; padding: 20px; }
    .header { background: #0078d4; color: white; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
    .box { background: white; border-radius: 8px; margin-bottom: 10px; border: 1px solid #ddd; overflow: hidden; }
    .box-header { background: #e9ecef; padding: 12px; cursor: pointer; font-weight: bold; display: flex; justify-content: space-between; }
    .box-content { padding: 15px; display: block; white-space: pre-wrap; font-family: monospace; font-size: 13px; }
    .green { color: #28a745; font-weight: bold; }
    .red { color: #dc3545; font-weight: bold; }
    .yellow { color: #d4a017; font-weight: bold; }
    .telemetry { background: #1e1e1e; color: #d4d4d4; }
    .system-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; padding: 15px; background: #f8f9fa; border-bottom: 1px solid #ddd; }
    .sys-card { padding: 10px; border-left: 3px solid #0078d4; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }
    .sys-card h4 { margin: 0 0 5px 0; color: #0078d4; text-transform: uppercase; font-size: 10px; letter-spacing: 1px; }
    .sys-val { font-size: 14px; font-weight: bold; font-family: monospace; }
</style>
<script>
    function toggleBox(el) { var c = el.nextElementSibling; c.style.display = (c.style.display === "none") ? "block" : "none"; }
    function toggleAll(show) { var contents = document.getElementsByClassName("box-content"); for (var i = 0; i < contents.length; i++) { contents[i].style.display = show ? "block" : "none"; } }
</script></head>
<body>
    <div class="header"><h2>LLM Diagnostics Report (Sanitized)</h2><p>v$ScriptVersion | $ReportDate</p></div>
    <div style="margin-bottom:15px;"><button onclick="toggleAll(true)">Expand All</button> <button onclick="toggleAll(false)">Collapse All</button></div>
    
    <div class="box">
        <div class="box-header" onclick="toggleBox(this)">1. System <span>[+/-]</span></div>
        <div class="box-content">
            <div class="system-grid">
                <div class="sys-card"><h4>CPU Load</h4><div class="sys-val">$cpuMetric</div></div>
                <div class="sys-card"><h4>RAM Usage</h4><div class="sys-val">$ramMetric</div></div>
                <div class="sys-card"><h4>VRAM Usage</h4><div class="sys-val">$vramMetric</div></div>
                <div class="sys-card"><h4>Disk Usage</h4><div class="sys-val">$diskMetric</div></div>
            </div>
$foundationClean
        </div>
    </div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">2. System LLM Optimizations <span>[+/-]</span></div><div class="box-content">$($sections.Windows -replace '\[\+\](.*)', '<span class="green">[+] `$1</span>' -replace '\[-\](.*)', '<span class="red">[-] `$1</span>' -replace '\[!\](.*)', '<span class="yellow">[!] `$1</span>')</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">3. Compute (GPU & PCIe Link) <span>[+/-]</span></div><div class="box-content">$($sections.Compute)</div></div>
    $vulkanTable
    <div class="box"><div class="box-header" onclick="toggleBox(this)">4. Vulkan Compute Detail <span>[+/-]</span></div><div class="box-content">$($sections.Vulkan)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">5. Active Clocks (ROCm-SMI) <span>[+/-]</span></div><div class="box-content telemetry">$($sections.Clocks)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">6. VRAM Allocation Telemetry <span>[+/-]</span></div><div class="box-content telemetry">$($sections.VRAM_Tele)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">7. Live Telemetry (Sampling) <span>[+/-]</span></div><div class="box-content telemetry">$($sections.Telemetry)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">8. AMD HIP Detail <span>[+/-]</span></div><div class="box-content">$($sections.HIP)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">9. Detected Runtimes and Ports Used <span>[+/-]</span></div><div class="box-content">$($sections.Runtimes -replace '\[\+\](.*)', '<span class="green">[+] `$1</span>' -replace '\[-\](.*)', '<span class="red">[-] `$1</span>' -replace '\[!\](.*)', '<span class="yellow">[!] `$1</span>')</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">10. Environment Variables <span>[+/-]</span></div><div class="box-content">$($sections.Env)</div></div>
    <div class="box"><div class="box-header" onclick="toggleBox(this)">11. System PATH (Formatted) <span>[+/-]</span></div><div class="box-content">$($sections.Path)</div></div>

    <div class="header" style="background: #34495e; margin-top: 40px;">
        <h3>Project Roadmap</h3>
        <p>Upcoming features and planned improvements</p>
    </div>
    <div class="box">
        <div class="box-content" style="font-family: sans-serif; font-size: 13px;">
            <ul style="line-height: 1.6;">
                <li><strong>Vulkan Hybrid Support:</strong> Expand diagnostics for mixed AMD/NVIDIA setups (e.g., RTX 3060 + Radeon) using Vulkan runtimes.</li>
                <li><strong>NVIDIA Integration:</strong> Full <code>nvidia-smi</code> support for telemetry and VRAM pooling on NVIDIA hardware.</li>
                <li><strong>Vulkan Performance Profiling:</strong> Investigate Vulkan-specific bottlenecks and shader compilation stutters.</li>
                <li><strong>Public Release (GitHub):</strong> Finalize documentation and sanitization for open-source publication.</li>
            </ul>
        </div>
    </div>

    <div class="header" style="background: #c0392b; margin-top: 40px;">
        <h3>Bottleneck Analysis</h3>
        <p>Automated detection of performance limiters</p>
    </div>
    <div class="box">
        <div class="box-content">
$bottleneckHtml
        </div>
    </div>


    <div class="header" style="background: #2c3e50; margin-top: 40px;">
        <h3>LLM Resource Hub & Downloads</h3>
        <p>Essential tools for AMD-centric LLM environments</p>
    </div>
    
    <div class="box">
        <div class="box-content" style="font-family: sans-serif; font-size: 14px;">
            <ul style="line-height: 1.8;">
                <li><strong>AMD HIP SDK (ROCm for Windows):</strong> <a href="https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html" target="_blank">Download Official SDK</a></li>
                <li><strong>Ollama For AMD Installer (Byron's Tool):</strong> <a href="https://github.com/ByronLeeeee/Ollama-For-AMD-Installer" target="_blank">GitHub Repository</a></li>
                <li><strong>KoboldCPP:</strong> <a href="https://github.com/LostRuins/koboldcpp/releases" target="_blank">Latest Releases</a></li>
                <li><strong>LM Studio:</strong> <a href="https://lmstudio.ai/" target="_blank">Official Website</a></li>
                <li><strong>AnythingLLM:</strong> <a href="https://useanything.com/download" target="_blank">Desktop Download</a></li>
            </ul>
            <hr style="margin: 20px 0; border: 0; border-top: 1px solid #eee;">
            <p style="font-size: 12px; opacity: 0.7;"><strong>Session Debugging:</strong> <a href="diag_session.log" target="_blank">View Session Log (diag_session.log)</a></p>
        </div>
    </div>
</body></html>
"@
    Sanitize-Text $htmlBody | Out-File "report.html"
    Write-Diag "Report Generated: $diagDir\report.html"
    Write-Host "Report Generated: $diagDir\report.html" -ForegroundColor Green
}

# --- MAIN MENU ---
while ($true) {
    Clear-Host
    $status = Get-TweakStatus
    Write-Host "=== LLM Diagnostics Tool v$ScriptVersion ===" -ForegroundColor Cyan
    Write-Host "System Status: " -NoNewline
    Write-Host "HPET: " -NoNewline; Write-Host $status.Log[0].Substring(10) -ForegroundColor $status.HPET -NoNewline
    Write-Host " | Pwr: " -NoNewline; Write-Host $status.Log[3].Substring(10) -ForegroundColor $status.Pwr
    Write-Host "--------------------------------------------"
    Write-Host "1. Gather Foundation Diag (Hardware & OS)"
    Write-Host "2. Gather Compute Diag (GPU & VRAM Map)"
    Write-Host "3. Gather Runtimes Diag (HIP, Path, Env Variables)"
    Write-Host "4. Capture LLM Runners & Processes"
    Write-Host "5. Capture System Performance (HPET, VBS, Power)"
    Write-Host "6. Change System Performance (Tuning Sub-Menu)"
    Write-Host "8. Run Full Diagnostics & Generate Report"
    Write-Host "T. Capture Live Telemetry (Clocks & VRAM)"
    Write-Host "9. Open Last Report"
    Write-Host "E. Exit"
    
    $choice = Read-Host "`nEnter choice"
    switch ($choice) {
        "1" { Check-HardwareOS; Pause }
        "2" { Check-GPUCompute; Pause }
        "3" { Check-RuntimesEnv; Pause }
        "4" { Check-Runners; Pause }
        "5" { Check-WindowsSystem; Pause }
        "6" { Show-TuningMenu }
        "8" { Check-HardwareOS; Check-GPUCompute; Check-RuntimesEnv; Check-Runners; Check-WindowsSystem; Check-Telemetry; Generate-HTML; Pause }
        "t" { Check-Telemetry; Pause }
        "9" { Start-Process "$diagDir\report.html" }
        { $_ -in "e", "E" } { exit }
    }
}
