# Windows Terminal File Finder

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-success?style=for-the-badge)

A high performance, terminal first Windows file search engine built with **PowerShell** and **.NET**.

Designed for developers, system administrators, and power users who need fast system wide file searching without relying on Windows Search indexing, background services, or graphical interfaces.

---

## Features

- Instant result streaming while scanning
- Smart Regex matching that reduces substring noise
- Search one drive, multiple drives, or the entire system
- Works with HDD, SSD, USB, and mapped network drives
- Interactive terminal commands while search is running
- Low memory usage using iterative stack based DFS traversal
- No Windows Search indexing required
- No background services
- Gracefully skips inaccessible directories
- Configuration stored automatically in `config.json`

---

## Why This Tool

Most Windows search utilities either depend on indexing or freeze until the scan completes.

Windows Terminal File Finder was built with a different approach.

- Results appear immediately
- Searches continue while you interact with previous results
- Minimal memory consumption
- Optimized for large file systems
- Fully terminal based

---

# Getting Started

## Run as a PowerShell Script

### 1. Open PowerShell as Administrator

Administrator privileges allow scanning protected system directories.

### 2. Enable Local Script Execution

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Run the Script

```powershell
.\FileFinder.ps1
```

---

# Build a Standalone Executable

Create a portable executable that can run without manually opening PowerShell.

## Install PS2EXE

```powershell
Install-Module ps2exe -Force -AcceptLicense
```

## Compile

```powershell
Invoke-ps2exe `
-inputFile ".\FileFinder.ps1" `
-outputFile ".\FileFinder.exe" `
-title "Windows File Finder" `
-requireAdmin
```

The `-requireAdmin` option automatically requests Administrator privileges when launching the executable.

After compilation, `FileFinder.exe` can be moved anywhere. A `config.json` file is automatically created beside the executable when needed.

---

# Interactive Commands

Results are streamed continuously and assigned IDs.

Example

```text
[1] C:\Projects\README.md
[2] D:\Downloads\Report.pdf
[3] E:\Photos\Image.png
```

Commands can be executed while the search is still running.

| Command | Example | Description |
|----------|----------|-------------|
| `open <id>` | `open 5` | Opens the selected file or folder using the default Windows application |
| `path <id>` | `path 2` | Opens File Explorer and highlights the selected file |
| `copy <id>` | `copy 12` | Copies the full absolute path to the Windows clipboard |

---

# Search Capabilities

Supports searching

- Single drive

```text
C:
```

- Multiple drives

```text
C:,D:,E:
```

- Entire system

```text
ALL
```

Supported storage

- Internal HDD
- Internal SSD
- External USB drives
- Mapped network drives

---

# Performance

Designed for large storage devices.

- Asynchronous result streaming
- Thread safe communication
- Low RAM consumption
- Non recursive traversal
- Handles millions of files efficiently
- Continues searching even when access is denied on protected folders

---

# Architecture

The application separates searching from user interaction.

## Main Thread

- Interactive command prompt
- Result rendering
- Configuration management
- User commands

## Background Runspace

- Filesystem traversal
- Directory enumeration
- Progress reporting
- Error handling

Communication between threads uses thread safe `.NET ConcurrentQueue` collections.

Filesystem enumeration uses

```text
EnumerateFileSystemInfos()
```

instead of loading entire directory contents into memory.

Traversal uses an iterative stack based depth first search to avoid recursion limits and reduce memory usage.

---

# Error Handling

The application safely skips

- Unauthorized directories
- Locked files
- System protected folders
- Inaccessible network paths

The search continues without interruption.

---

# Project Goals

- Fast
- Lightweight
- Reliable
- Terminal first
- No indexing
- No unnecessary dependencies

---

# License

Released under the MIT License.

---

# Acknowledgements

Thank you for checking out this project.

The goal of this utility is simple

Build a fast, reliable, developer focused Windows file search tool that stays lightweight while remaining powerful enough for everyday system wide searching.

If this project helps you, consider giving it a star.

