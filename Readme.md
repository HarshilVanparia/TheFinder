# ⚡ Windows Terminal File Finder

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg?logo=powershell)
![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6.svg?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green.svg)

A high-performance, completely terminal-based Windows file search engine. Designed for developers and power users who want rapid, system-wide search capabilities entirely within the command line—with zero GUI dependencies, zero background indexing, and a minimal memory footprint.

## ✨ Key Features

* **Asynchronous Streaming:** Results appear instantly as they are found. You don't have to wait for the entire drive scan to finish.
* **Smart Match Regex:** Intelligently filters out substring noise (e.g., searching `ration` finds `ration.txt` but ignores `operation.exe`).
* **Multi-Drive Scanning:** Search a single drive, a comma-separated list of drives, or your entire system (HDD, SSD, USB, and Mapped Network Drives) simultaneously.
* **Low Memory Usage:** Utilizes iterative Stack-based DFS traversal instead of recursion to prevent stack overflows and minimize RAM usage on massive filesystems.
* **Interactive Command Line:** Interact with streamed results in real-time without stopping the search engine.
* **Click-to-Reveal:** Supports native Windows Terminal hyperlink detection. Hold `Ctrl` and click any result path to open it directly in Explorer.

---

## 🚀 Usage (Running as a Script)

If you prefer to run the script natively without compiling:

1. Open PowerShell as Administrator (to bypass access restrictions on system folders).
2. Ensure your execution policy allows local scripts:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser