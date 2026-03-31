/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import { motion } from "motion/react";
import { 
  Activity, 
  Cpu, 
  Database, 
  Download, 
  FileText, 
  HardDrive, 
  Layers, 
  Shield, 
  Zap,
  Terminal,
  Settings,
  Info,
  AlertTriangle,
  ExternalLink,
  LayoutDashboard,
  ShieldCheck
} from "lucide-react";
import { useState } from "react";

export default function App() {
  const [activeTab, setActiveTab] = useState("overview");

  const features = [
    { id: "foundation", icon: <HardDrive className="w-4 h-4" />, label: "Hardware & OS", description: "CPU, RAM, and Disk health checks." },
    { id: "compute", icon: <Cpu className="w-4 h-4" />, label: "GPU Compute", description: "AMD ROCm/HIP detection and VRAM mapping." },
    { id: "runtimes", icon: <Layers className="w-4 h-4" />, label: "Runtimes", description: "Environment variables and PATH auditing." },
    { id: "runners", icon: <Activity className="w-4 h-4" />, label: "LLM Runners", description: "Active process detection for Ollama, LM Studio, etc." },
    { id: "performance", icon: <Zap className="w-4 h-4" />, label: "Performance Audit", description: "HPET, VBS, and Power Plan analysis." },
    { id: "tuning", icon: <Settings className="w-4 h-4" />, label: "System Tuning", description: "One-click optimizations with registry safety." },
  ];

  return (
    <div className="min-h-screen bg-[#E4E3E0] text-[#141414] font-sans selection:bg-[#141414] selection:text-[#E4E3E0]">
      {/* Header */}
      <header className="border-b border-[#141414] p-6 flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tighter flex items-center gap-2">
            <Terminal className="w-6 h-6" />
            LLMDIAG.ps1 <span className="text-xs font-mono opacity-50">.319</span>
          </h1>
          <p className="text-xs font-mono opacity-60 uppercase tracking-widest mt-1">
            Diagnostics & Tuning Suite for Local LLM Environments
          </p>
        </div>
        <div className="flex gap-4">
          <button className="px-4 py-2 border border-[#141414] text-xs font-mono hover:bg-[#141414] hover:text-[#E4E3E0] transition-colors flex items-center gap-2">
            <Download className="w-3 h-3" />
            DOWNLOAD SCRIPT
          </button>
        </div>
      </header>

      <main className="grid grid-cols-1 lg:grid-cols-12 min-h-[calc(100vh-88px)]">
        {/* Sidebar Navigation */}
        <nav className="lg:col-span-3 border-r border-[#141414] p-6 space-y-1">
          <p className="text-[10px] font-mono opacity-40 uppercase tracking-widest mb-4 italic">Navigation</p>
          {["overview", "diagnostics", "telemetry", "tuning", "reports", "resources"].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`w-full text-left px-4 py-3 text-sm font-mono uppercase tracking-tight transition-all flex justify-between items-center ${
                activeTab === tab ? "bg-[#141414] text-[#E4E3E0]" : "hover:bg-[#141414]/5"
              }`}
            >
              {tab}
              {activeTab === tab && <div className="w-1.5 h-1.5 bg-[#E4E3E0] rounded-full" />}
            </button>
          ))}

          <div className="mt-12 p-4 border border-[#141414]/20 bg-white/50">
            <p className="text-[10px] font-mono opacity-60 flex items-center gap-1 mb-2">
              <Shield className="w-3 h-3" /> SECURITY STATUS
            </p>
            <p className="text-xs font-mono text-green-700 font-bold">SANITY CHECK: PASSED</p>
            <p className="text-[9px] font-mono opacity-40 mt-2 leading-tight">
              Privacy Sanitizer active. Usernames are masked in all generated reports.
            </p>
          </div>
        </nav>

        {/* Content Area */}
        <section className="lg:col-span-9 p-8">
          {activeTab === "overview" && (
            <motion.div 
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="space-y-8"
            >
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="p-6 border border-[#141414] bg-white">
                  <h2 className="font-serif italic text-xl mb-4">The Mission</h2>
                  <p className="text-sm leading-relaxed opacity-80">
                    LLMDIAG is designed for the modern Local LLM enthusiast. Specifically optimized for 
                    <span className="font-bold"> AMD ROCm/HIP</span> environments, it bridges the gap between 
                    raw hardware and optimized inference performance.
                  </p>
                </div>
                <div className="p-6 border border-[#141414] bg-[#141414] text-[#E4E3E0]">
                  <h2 className="font-serif italic text-xl mb-4">Quick Start</h2>
                  <code className="text-xs block bg-white/10 p-4 rounded mb-4">
                    powershell.exe -ExecutionPolicy Bypass -File .\LLMDIAG.ps1
                  </code>
                  <p className="text-[10px] font-mono opacity-60">
                    Requires Administrator privileges for performance tuning (HPET/BCD/Registry).
                  </p>
                </div>
              </div>

              <div>
                <h3 className="text-[10px] font-mono opacity-40 uppercase tracking-widest mb-4 italic">Core Modules</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  {features.map((f) => (
                    <div key={f.id} className="p-4 border border-[#141414]/10 bg-white/30 hover:bg-white transition-colors group cursor-default">
                      <div className="flex items-center gap-2 mb-2">
                        <div className="p-1.5 bg-[#141414] text-[#E4E3E0] group-hover:scale-110 transition-transform">
                          {f.icon}
                        </div>
                        <span className="text-xs font-bold uppercase tracking-tight">{f.label}</span>
                      </div>
                      <p className="text-[11px] opacity-60 leading-tight">{f.description}</p>
                    </div>
                  ))}
                </div>
              </div>

              <div className="p-6 border border-dashed border-[#141414]/30">
                <h3 className="font-serif italic text-lg mb-4 flex items-center gap-2">
                  <Info className="w-4 h-4" /> Why Tuning Matters
                </h3>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-8">
                  <div>
                    <p className="text-[10px] font-mono font-bold uppercase mb-1">HPET Latency</p>
                    <p className="text-xs opacity-60">High Precision Event Timer can cause micro-stuttering during token generation. Disabling it stabilizes frametimes.</p>
                  </div>
                  <div>
                    <p className="text-[10px] font-mono font-bold uppercase mb-1">Power Throttling</p>
                    <p className="text-xs opacity-60">Standard power plans park CPU cores aggressively, introducing latency when the LLM runner requests compute.</p>
                  </div>
                  <div>
                    <p className="text-[10px] font-mono font-bold uppercase mb-1">VBS Impact</p>
                    <p className="text-xs opacity-60">Virtualization-Based Security is great for safety but can cost 5-15% in raw compute throughput for LLMs.</p>
                  </div>
                </div>
              </div>
            </motion.div>
          )}

          {activeTab === "diagnostics" && (
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="space-y-4"
            >
              <h2 className="font-serif italic text-2xl">Diagnostic Engine</h2>
              <div className="bg-[#141414] text-[#E4E3E0] p-6 font-mono text-xs overflow-x-auto">
                <p className="text-green-400">[INFO] Initializing LLMDIAG .319...</p>
                <p>[INFO] Detecting AMD Compute Layer...</p>
                <p className="text-green-400">[OK] Found RX 9060 XT [Dedicated]</p>
                <p className="text-green-400">[OK] Found RTX 3060 [Dedicated] - Vulkan Mode</p>
                <p>[INFO] Mapping LUIDs to Hardware Labels...</p>
                <p>[INFO] System: RAM (12GB/64GB), CPU (5s Avg: 6.8%), VRAM (4.2GB/24.5GB)</p>
                <p className="text-green-400">[OK] Vulkan Extensions: VK_KHR_shader_float16_int8, VK_KHR_variable_pointers</p>
                <p className="text-green-400">[OK] Session Log initialized: diag_session.log</p>
                <p className="animate-pulse">_</p>
              </div>
              <p className="text-xs opacity-60 italic">Simulation of diagnostic output. Run the script for live results.</p>
            </motion.div>
          )}

          {activeTab === "telemetry" && (
            <motion.div 
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              className="space-y-8"
            >
              <div className="flex justify-between items-end">
                <h2 className="font-serif italic text-2xl">Live Telemetry & Load Monitor</h2>
                <span className="text-[10px] font-mono bg-red-500 text-white px-2 py-0.5 animate-pulse">SAMPLING UNDER LOAD</span>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                <div className="p-4 border border-[#141414] bg-white">
                  <p className="text-[10px] font-mono opacity-50 uppercase">9060 XT [D]</p>
                  <p className="text-lg font-bold">x16 @ Gen 5</p>
                  <p className="text-[9px] text-green-600 font-bold mt-1">2780 MHz / 1361 MHz</p>
                </div>
                <div className="p-4 border border-[#141414] bg-white">
                  <p className="text-[10px] font-mono opacity-50 uppercase">6600 [D]</p>
                  <p className="text-lg font-bold">x16 @ Gen 4</p>
                  <p className="text-[9px] text-green-600 font-bold mt-1">2044 MHz / 875 MHz</p>
                </div>
                <div className="p-4 border border-[#141414] bg-white">
                  <p className="text-[10px] font-mono opacity-50 uppercase">iGPU [Radeon]</p>
                  <p className="text-lg font-bold">Integrated</p>
                  <p className="text-[9px] text-blue-600 font-bold mt-1">UI OFFLOAD ACTIVE</p>
                </div>
                <div className="p-4 border border-[#141414] bg-white">
                  <p className="text-[10px] font-mono opacity-50 uppercase">Pagefile</p>
                  <p className="text-lg font-bold">8.0 GB</p>
                  <p className="text-[9px] text-yellow-600 font-bold mt-1">DYNAMIC (TWEAK REQ)</p>
                </div>
              </div>

              <div className="p-6 border border-yellow-200 bg-yellow-50">
                <h3 className="text-yellow-800 font-bold text-sm mb-2 uppercase tracking-widest flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4" />
                  Bottleneck Analysis (.319)
                </h3>
                <div className="space-y-2 text-xs font-mono text-yellow-700">
                  <p className="text-green-700">[OK] VK_KHR_variable_pointers: Supported (Vital for AI).</p>
                  <p className="text-red-700">[ISSUE] High VRAM Usage: GPU is using 74.2% of VRAM.</p>
                  <p className="text-yellow-700">[POTENTIAL] Low VRAM Availability: 2.1 GB free.</p>
                  <p className="text-yellow-700">[STABILITY] Recommendation: Set Pagefile to Fixed 8192MB.</p>
                </div>
              </div>

              <div className="p-6 border border-[#141414] bg-[#1e1e1e] text-[#d4d4d4] font-mono text-xs">
                <h3 className="text-white mb-4 border-b border-white/10 pb-2">Service & Latency Audit</h3>
                <div className="space-y-1">
                  <p className="flex justify-between"><span>[11434] Ollama:</span> <span className="text-green-400">LISTENING (PID 4520)</span></p>
                  <p className="flex justify-between"><span>[5001] KoboldCPP:</span> <span className="text-green-400">ACTIVE (Latency: 42ms)</span></p>
                  <p className="flex justify-between"><span>[8080] Web UI:</span> <span className="text-red-400">CONFLICT (PID 6128)</span></p>
                </div>
              </div>

              <div className="p-4 border border-dashed border-[#141414]/30">
                <p className="text-[10px] font-mono opacity-60 italic">
                  Note: Telemetry is captured over a 10s loop. For accurate results, ensure your LLM is 
                  actively generating tokens while the script is sampling.
                </p>
              </div>
            </motion.div>
          )}

          {activeTab === "tuning" && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
              <div className="space-y-6">
                <h2 className="font-serif italic text-2xl">Optimization Suite</h2>
                <div className="space-y-4">
                  <div className="p-4 border border-[#141414] bg-white flex justify-between items-center">
                    <div>
                      <p className="text-xs font-bold uppercase">Disable HPET</p>
                      <p className="text-[10px] opacity-60">Reduces timer jitter for smoother inference.</p>
                    </div>
                    <div className="px-2 py-1 bg-red-100 text-red-700 text-[10px] font-bold">RECOMMENDED</div>
                  </div>
                  <div className="p-4 border border-[#141414] bg-white flex justify-between items-center">
                    <div>
                      <p className="text-xs font-bold uppercase">Ultimate Power Plan</p>
                      <p className="text-[10px] opacity-60">Prevents CPU core parking.</p>
                    </div>
                    <div className="px-2 py-1 bg-green-100 text-green-700 text-[10px] font-bold">OPTIMIZED</div>
                  </div>
                </div>
              </div>
              <div className="p-6 bg-white border border-[#141414]">
                <h3 className="text-xs font-bold uppercase mb-4 flex items-center gap-2">
                  <Database className="w-4 h-4" /> Backup & Safety
                </h3>
                <p className="text-xs mb-4 opacity-70">
                  Every change is logged and backed up. The script creates incremental restore points 
                  for Registry, BCD, and Power configurations.
                </p>
                <div className="space-y-2">
                  <div className="flex justify-between text-[10px] font-mono border-b border-[#141414]/10 pb-1">
                    <span>bkp1_20240222</span>
                    <span className="text-green-600">VALID</span>
                  </div>
                  <div className="flex justify-between text-[10px] font-mono border-b border-[#141414]/10 pb-1">
                    <span>bkp2_20240222</span>
                    <span className="text-green-600">VALID</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === "reports" && (
            <div className="flex flex-col items-center justify-center h-full opacity-30">
              <FileText className="w-16 h-16 mb-4" />
              <p className="font-serif italic text-xl">No reports found in session.</p>
              <p className="text-xs font-mono">Run the script to generate HTML reports.</p>
            </div>
          )}

          {activeTab === "resources" && (
            <motion.div 
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              className="space-y-8"
            >
              <h2 className="font-serif italic text-2xl">LLM Resource Hub</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="p-6 border border-[#141414] bg-white">
                  <h3 className="text-xs font-bold uppercase mb-4 flex items-center gap-2">
                    <Cpu className="w-4 h-4" /> Compute & Drivers
                  </h3>
                  <ul className="space-y-3">
                    <li>
                      <a href="https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html" target="_blank" className="text-sm font-mono hover:underline flex items-center gap-2">
                        <Download className="w-3 h-3" /> AMD HIP SDK (ROCm)
                      </a>
                      <p className="text-[10px] opacity-60 ml-5">Essential for AMD GPU compute on Windows.</p>
                    </li>
                    <li>
                      <a href="https://github.com/ByronLeeeee/Ollama-For-AMD-Installer" target="_blank" className="text-sm font-mono hover:underline flex items-center gap-2">
                        <Download className="w-3 h-3" /> Byron's AMD Installer
                      </a>
                      <p className="text-[10px] opacity-60 ml-5">Streamlined Ollama setup for AMD hardware.</p>
                    </li>
                  </ul>
                </div>

                <div className="p-6 border border-[#141414] bg-white">
                  <h3 className="text-xs font-bold uppercase mb-4 flex items-center gap-2">
                    <Activity className="w-4 h-4" /> LLM Runners
                  </h3>
                  <ul className="space-y-3">
                    <li>
                      <a href="https://lmstudio.ai/" target="_blank" className="text-sm font-mono hover:underline flex items-center gap-2">
                        <Download className="w-3 h-3" /> LM Studio
                      </a>
                      <p className="text-[10px] opacity-60 ml-5">Premium GUI for local LLM discovery and chat.</p>
                    </li>
                    <li>
                      <a href="https://github.com/LostRuins/koboldcpp/releases" target="_blank" className="text-sm font-mono hover:underline flex items-center gap-2">
                        <Download className="w-3 h-3" /> KoboldCPP
                      </a>
                      <p className="text-[10px] opacity-60 ml-5">High-performance runner with GGUF support.</p>
                    </li>
                  </ul>
                </div>
              </div>

              <div className="p-6 border border-dashed border-[#141414]/30 bg-[#141414]/5">
                <h3 className="text-xs font-bold uppercase mb-2">Community & Documentation</h3>
                <div className="flex flex-wrap gap-4">
                  <a href="https://useanything.com/" target="_blank" className="text-[10px] font-mono uppercase tracking-widest px-3 py-1 border border-[#141414] hover:bg-[#141414] hover:text-[#E4E3E0] transition-colors">AnythingLLM</a>
                  <a href="https://github.com/ROCm/ROCm" target="_blank" className="text-[10px] font-mono uppercase tracking-widest px-3 py-1 border border-[#141414] hover:bg-[#141414] hover:text-[#E4E3E0] transition-colors">ROCm GitHub</a>
                  <a href="https://reddit.com/r/LocalLLaMA" target="_blank" className="text-[10px] font-mono uppercase tracking-widest px-3 py-1 border border-[#141414] hover:bg-[#141414] hover:text-[#E4E3E0] transition-colors">r/LocalLLaMA</a>
                </div>
              </div>
            </motion.div>
          )}
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-[#141414] p-4 flex justify-between items-center bg-white/50">
        <p className="text-[10px] font-mono opacity-40">
          &copy; 2024 LLMDIAG PROJECT | AMD ROCm/HIP SPECIALIST EDITION
        </p>
        <div className="flex gap-4 text-[10px] font-mono opacity-60">
          <span className="flex items-center gap-1"><Activity className="w-3 h-3" /> SYSTEM STABLE</span>
          <span className="flex items-center gap-1"><Shield className="w-3 h-3" /> ADMIN MODE REQ</span>
        </div>
      </footer>
    </div>
  );
}
