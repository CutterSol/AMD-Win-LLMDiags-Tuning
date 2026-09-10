LLMDIAG — AMD-Centric LLM Diagnostic & Tuning Tool for Windows

A self-elevating PowerShell diagnostic tool built for Windows-based local LLM environments, with a focus on AMD hardware (ROCm/Vulkan) and optimized for infrastructure use.  Also supports Vulkan and various LLM Engines that run on Windows.  

## What It Does

LLMDIAG collects system telemetry across five stages—hardware foundation, GPU compute layers, runtimes/environment, active LLM processes, and Windows optimization settings—and generates a comprehensive HTML report with automated bottleneck analysis.  It can also be used to configure base settings essential to LLMs as well as Video Games!

### Key Features

- **VRAM >4GB Fix** — Corrects the WMI uint32 cap on modern AMD cards by falling back to Registry values via `HardwareInformation.MemorySize`
- **ROCm & Vulkan Integration** — Checks ROCm drivers, HIP SDK availability, and Vulkan AI extensions (variable pointers, memory budget, shader int8/16)
- **LLM Footprint Audit** — Measures active LLM process VRAM consumption and flags spillover into shared system memory
- **Bottleneck Analysis Engine** — Detects VRAM overflow (>250MB), PCIe bandwidth limits (x4+ required), port conflicts, and pagefile configuration
- **System Tuning Menu** — Apply HPET disable, Ultimate Power Plan, or Network Throttling tweaks with backup/restore capability
- **Live Telemetry Sampling** — 10-second ROCm-SMI and Performance Counter sampling under load
- **Readiness Score** — 100-point weighted score covering VRAM capacity (40%), AVX instructions (10%), tuning state (50%), and bottleneck penalties

## Prerequisites

- Windows 10 or 11 (tested on Windows 10 only, in June of 2026)
- PowerShell 5.1+
- AMD Adrenalin drivers or ROCm/AMD HIP SDK (hipinfo adds detailed telemetry)
- No external dependencies — runs on stock Windows

## Quick Start

```powershell
# Clone and run the batch wrapper (auto-elevates to Administrator)
LLMDIAG.bat
```

Or run directly from PowerShell:

```powershell
Start-Process powershell -Verb runAs -ArgumentList "-ExecutionPolicy Bypass -File LLMDIAG.ps1"
```

## Diagnostic Flow

The tool offers both individual stage execution and a full diagnostic suite:

| Option | Stage | What It Checks |
|--------|-------|----------------|
| 1 | Foundation | CPU load, RAM, VRAM (all adapters), disk, pagefile config |
| 2 | Compute | GPU hardware, PCIe link state, Vulkan extensions, ROCm clocks |
| 3 | Runtimes & Environment | HIP/ROCm env vars, HSA overrides, PATH verification |
| 4 | Runners | Active LLM processes (LM Studio, Ollama, KoboldCPP, AnythingLLM), port usage and conflicts |
| 5 | Windows System | HPET status, VBS state, Network Throttling, Power Plan, WSL2 detection |
| T | Live Telemetry | 10s sampling of ROCm-SMI or GPU Performance Counters under load |
| 8 | Full Suite | Runs all stages + telemetry capture and HTML report generation |

## Tuning Sub-Menu (Option 6)

The built-in tuning menu lets you modify system settings with full backup/restore:

1. **Disable HPET** — Removes `useplatformclock` from BCD to reduce timer jitter
2. **Ultimate Power Plan** — Unlocks and activates the Ultimate Performance profile
3. **Network & Responsiveness** — Sets SystemResponsiveness to 0, NetworkThrottlingIndex to -1

All tweaks are backed up before application. Restore uses the most recent backup folder.

## Output

- **HTML Report** (`report.html`) — Self-contained with expandable sections, color-coded indicators, bottleneck analysis, and LLM resource hub
- **Session Log** (`diag_session.log`) — Timestamped diagnostic session trace
- **Stage Files** — Individual `.txt` files for each diagnostic stage (hardware_os.txt, GPU.txt, vulkan_info.txt, etc.)
- **Backup Folders** — Dated backup directories in `C:\_LLMDiag\TweakBackups\bkpX`

## AMD Focus Notes

This tool was developed and tested on an AMD V620, RX 9060 XT, & RX 7700 16GB with Ryzen 5000 host. It prioritizes:
- ROCm/hipinfo telemetry over nvidia-smi
- Vulkan-based AI extension detection for RDNA architectures
- HSA_OVERRIDE_GFX_VERSION awareness

NVIDIA cards are detected and handled via fallback heuristics, with full support planned in upcoming releases.

## Session Management

Each run creates a numbered directory under `C:\_LLMDiag\` (e.g., `LLMDiag1`, `LLMDiag2`). Diagnostics run within this session directory for isolation.

## Version History

Current: v0.3.18

## License

MIT
```
