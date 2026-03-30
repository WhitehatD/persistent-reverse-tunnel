# 🔗 Persistent Reverse SSH Tunnel

**Enterprise-grade, self-healing reverse SSH tunnel for NAT-restricted environments.**

Access your home machine from anywhere — even behind ISP firewalls, double NAT, or building-managed modems that block port forwarding — by routing through a cloud VPS.

[![OS](https://img.shields.io/badge/OS-Windows%2011-0078D6?style=for-the-badge&logo=windows11)](https://www.microsoft.com/windows)
[![SSH](https://img.shields.io/badge/Protocol-OpenSSH-231F20?style=for-the-badge&logo=openssh)](https://www.openssh.com/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

---

## The Problem

```
You                    Building Modem              Your Laptop
(Phone/Remote PC) --X--> [NAT / No Port Forward] --|--> Can't reach it
```

Many residential and commercial ISPs place customers behind **carrier-grade NAT (CGNAT)** or building-managed routers that **do not allow port forwarding**. This makes it impossible to SSH into your home machine from outside.

## The Solution

Flip the direction. Your laptop initiates an **outbound** SSH connection to a VPS you control, and opens a **reverse tunnel** that the VPS exposes as a port. You then SSH into the VPS port, which routes through the tunnel to your laptop.

```
You (anywhere) --> VPS:2222 --[reverse tunnel]--> Laptop:22 ✓
```

No port forwarding required. No firewall changes. Works on any internet connection.

---

## Architecture

```mermaid
flowchart TB
    subgraph INTERNET["☁️ Internet"]
        direction TB
        PHONE["📱 Phone<br/><small>Termius / JuiceSSH</small>"]
        REMOTE["💻 Remote PC"]
    end

    subgraph VPS["🖥️ Cloud VPS"]
        direction TB
        SSHD_VPS["OpenSSH Server<br/><small>Port 22 (management)</small><br/><small>Port 2222 (tunnel)</small>"]
        FW["Firewall<br/><small>UFW / iptables</small>"]
    end

    subgraph HOME["🏠 Behind NAT"]
        direction TB
        MODEM["🚫 Building Modem<br/><small>No port forwarding</small>"]
        LAPTOP["💻 Laptop<br/><small>OpenSSH Server on :22</small>"]
        TUNNEL_SVC["🔄 Tunnel Service<br/><small>Task Scheduler</small>"]
    end

    PHONE -->|"ssh -p 2222<br/>user@vps-ip"| SSHD_VPS
    REMOTE -->|"ssh -p 2222<br/>user@vps-ip"| SSHD_VPS
    SSHD_VPS <-->|"Reverse Tunnel<br/>VPS:2222 ↔ Laptop:22"| MODEM
    MODEM <--> LAPTOP
    TUNNEL_SVC -->|"Outbound SSH<br/>(always-on)"| MODEM
    TUNNEL_SVC -.->|manages| LAPTOP

    style INTERNET fill:#1a1a2e,stroke:#16213e,color:#eee
    style VPS fill:#0f3460,stroke:#533483,color:#eee
    style HOME fill:#1a1a2e,stroke:#e94560,color:#eee
    style MODEM fill:#e94560,stroke:#e94560,color:#fff
    style PHONE fill:#533483,stroke:#533483,color:#fff
    style REMOTE fill:#533483,stroke:#533483,color:#fff
    style SSHD_VPS fill:#0f3460,stroke:#00d2ff,color:#eee
    style LAPTOP fill:#16213e,stroke:#00d2ff,color:#eee
    style TUNNEL_SVC fill:#16213e,stroke:#00ff88,color:#eee
    style FW fill:#0f3460,stroke:#ff6600,color:#eee
```

---

## Connection Flow

```mermaid
sequenceDiagram
    participant L as 💻 Laptop
    participant M as 🚫 Modem (NAT)
    participant V as 🖥️ VPS
    participant P as 📱 Phone

    Note over L: Tunnel service starts<br/>(boot / logon)

    L->>M: Outbound SSH (port 22)
    M->>V: Passes through NAT ✓
    V-->>V: Binds port 2222<br/>→ reverse tunnel

    Note over L,V: 🔗 Tunnel established

    loop Every 15 seconds
        L->>V: ServerAlive keepalive
        V-->>L: ServerAlive reply
    end

    P->>V: ssh -p 2222 user@vps-ip
    V->>L: Routes through tunnel
    L-->>V: Shell session data
    V-->>P: Shell session data

    Note over P: Full shell access ✓

    rect rgb(80, 20, 20)
        Note over L,V: ⚠️ Connection drops
        V--xL: Timeout (3 missed keepalives)
        L->>L: Detect failure, backoff 5s
        L->>M: Reconnect SSH
        M->>V: Re-establish tunnel
        Note over L,V: 🔗 Tunnel restored
    end
```

---

## Reconnection & Self-Healing

```mermaid
stateDiagram-v2
    [*] --> Connecting: Service starts

    Connecting --> Connected: SSH handshake OK
    Connecting --> Backoff: Connection failed

    Connected --> Monitoring: Tunnel bound on VPS

    Monitoring --> Connected: Keepalive OK (every 15s)
    Monitoring --> Disconnected: 3 missed keepalives

    Disconnected --> Backoff: SSH process exits

    Backoff --> Connecting: Wait expires

    state Backoff {
        [*] --> 5s
        5s --> 10s: Still failing
        10s --> 20s: Still failing
        20s --> 40s: Still failing
        40s --> 60s_cap: Still failing
        60s_cap --> 60s_cap: Max backoff
    }

    note right of Monitoring
        Stable > 5 min
        resets backoff to 5s
    end note

    note right of Connected
        ExitOnForwardFailure=yes
        prevents silent binding failures
    end note
```

---

## Components

### 1. VPS — SSH Server Configuration

The VPS SSH daemon is configured to support reverse tunnels with keepalive detection.

```
# /etc/ssh/sshd_config.d/tunnel.conf
GatewayPorts yes              # Allow remote port binding
AllowTcpForwarding yes        # Permit tunnel forwarding
ClientAliveInterval 30        # Check client every 30s
ClientAliveCountMax 3         # Drop after 3 misses (90s)
```

| Setting | Value | Purpose |
|---------|-------|---------|
| `GatewayPorts` | `yes` | Allows the reverse-bound port to accept connections from any interface |
| `AllowTcpForwarding` | `yes` | Permits `-R` and `-L` tunnel flags |
| `ClientAliveInterval` | `30` | Server-side keepalive every 30 seconds |
| `ClientAliveCountMax` | `3` | Drops dead connections after 90s of silence |

### 2. Laptop — OpenSSH Server

Windows 11's built-in OpenSSH Server accepts incoming connections through the tunnel.

```
# Installed via Windows capability
OpenSSH.Server~~~~0.0.1.0

# Service: sshd
# StartType: Automatic
# Auth: Public key (administrators_authorized_keys)
```

#### Default Shell Configuration

Windows OpenSSH defaults to CMD, which is unusable for development. To set Git Bash as the default SSH shell, use a `.cmd` wrapper — this is necessary because Windows OpenSSH passes `DefaultShellCommandOption` as a **single argument**, which breaks multi-flag options like `--login -i`.

**Wrapper script** (`shell.cmd`):
```cmd
@"C:\Program Files\Git\bin\bash.exe" --login -i
```

**Registry setup** (run as Administrator):
```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\path\to\shell.cmd" -PropertyType String -Force
Remove-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShellCommandOption -ErrorAction SilentlyContinue
Restart-Service sshd
```

> **Why a wrapper?** Setting `DefaultShell` directly to `bash.exe` with `DefaultShellCommandOption` set to `--login -i` or `-l -c` fails — Windows OpenSSH concatenates the option as one string argument, and Bash rejects it. The `.cmd` wrapper passes the flags correctly as separate arguments.

The `--login` flag makes Bash read `~/.bash_profile` on connect, where you can define aliases, set the default directory, and display a welcome message.

### 3. Laptop — Tunnel Service

A PowerShell script managed by **Windows Task Scheduler** maintains the reverse tunnel.

```
SSH Tunnel Process
├── Connection: ssh -N -R 2222:localhost:22 vps-user@vps-ip
├── Keepalive: ServerAliveInterval=15, ServerAliveCountMax=3
├── Safety: ExitOnForwardFailure=yes, BatchMode=yes
├── Reconnect: Exponential backoff (5s → 60s cap)
├── Network wait: Polls VPS:22 for up to 120s on boot
├── Log rotation: Auto-rotates at 10MB
├── Diagnostics: SSH stderr captured per connection attempt
└── Logging: tunnel.log with timestamps
```

**Task Scheduler Configuration:**

| Property | Value |
|----------|-------|
| Trigger | At startup (15-second delay for networking) |
| Run as | `SYSTEM` (ServiceAccount — has network credentials, runs before login) |
| Run level | Highest privileges |
| Battery | Runs on battery, doesn't stop on switch |
| Restart | Up to 999 retries, 1-minute interval |
| Time limit | Unlimited (no execution timeout) |
| Window | Hidden (no console window) |

> **Why SYSTEM, not S4U?** The original design used `S4U` (Service-for-User) logon type, which runs without a stored password. However, S4U tokens **do not carry network credentials** — the SSH process cannot make outbound connections and dies immediately. SYSTEM has full network access and runs at boot before any user logs in.

### 4. Key Authentication Chain

```mermaid
flowchart LR
    subgraph LAPTOP["Laptop"]
        LK["~/.ssh/id_rsa<br/><small>Private Key</small>"]
    end

    subgraph VPS["VPS"]
        VA["~/.ssh/authorized_keys<br/><small>Laptop's public key</small>"]
        VK["~/.ssh/id_tunnel<br/><small>Tunnel keypair</small>"]
    end

    subgraph LAPTOP_SSHD["Laptop SSHD"]
        LA["administrators_authorized_keys<br/><small>VPS tunnel public key</small>"]
    end

    LK -->|"Authenticates outbound tunnel"| VA
    VK -->|"Authenticates inbound sessions"| LA

    style LAPTOP fill:#16213e,stroke:#00d2ff,color:#eee
    style VPS fill:#0f3460,stroke:#533483,color:#eee
    style LAPTOP_SSHD fill:#16213e,stroke:#00ff88,color:#eee
```

**Two separate key pairs — no shared secrets:**
- **Laptop → VPS:** Laptop's RSA key authenticates the outbound tunnel connection
- **VPS → Laptop:** VPS's Ed25519 tunnel key authenticates inbound sessions through the tunnel

---

## Session Persistence

Mobile SSH clients (Termius, JuiceSSH) lose connections when the app goes to background — iOS and Android suspend TCP sockets, and the server drops the session within 90 seconds. This kills any long-running process on the remote end.

This project includes optional session persistence that solves this entirely. Sessions survive phone sleep, app kills, and network switches. Reconnecting reattaches to the exact same session — processes on the remote machine never notice the interruption.

### Setup

Run the installer on the VPS:
```bash
ssh root@<vps-ip> 'bash -s' < setup-phone-session.sh
```

Then update your mobile SSH client to connect on **port 22** (username `root`) instead of port 2222. The same key is used.

### How it works

The VPS acts as a session persistence layer between the phone and the laptop. The phone's connection is decoupled from the actual work session — disconnecting the phone doesn't affect the running processes.

See `phone-session.sh` and `setup-phone-session.sh` for implementation details.

---

## Mobile Access with Termius (Direct)

> **Note:** This method connects directly through the tunnel without persistence. Sessions will be lost if your phone goes to sleep. For persistent sessions, use the setup above.

### Step 1: Get the tunnel private key onto your phone

The VPS tunnel private key (`id_tunnel`) must be imported into your phone's SSH client. The key lives on the VPS at `~/.ssh/id_tunnel`.

**iPhone users — do NOT copy-paste the key.** iOS aggressively strips trailing whitespace from lines when copying from browsers and text views, which corrupts OpenSSH keys. Instead:

1. **Email the key to yourself as a file attachment:**
   - On your laptop, retrieve the key: `ssh root@<vps-ip> "cat ~/.ssh/id_tunnel" > tunnel-key.txt`
   - Open your email client, compose to yourself, attach `tunnel-key.txt`, send
   - On your phone, open the email and download the attachment

2. **Or use AirDrop (macOS → iPhone)** or a cloud drive (Google Drive, OneDrive) to transfer the file

3. **Or host it temporarily** on the VPS for 60 seconds:
   ```bash
   ssh root@<vps-ip> "cd /tmp && cp ~/.ssh/id_tunnel key.txt && python3 -m http.server 8888 &"
   # Download on phone: http://<vps-ip>:8888/key.txt
   # Then kill it:
   ssh root@<vps-ip> "pkill -f 'http.server 8888' && rm /tmp/key.txt"
   ```

> **Why not copy-paste?** OpenSSH private keys are base64-encoded with strict line formatting. A single missing character or extra newline will cause `invalid format` errors. File transfer preserves the exact bytes.

### Step 2: Import the key into Termius

1. Open Termius → **Keychain** → tap **+** → **Key**
2. Fill in:
   | Field | Value |
   |-------|-------|
   | **Label** | `laptop-tunnel` |
   | **Private Key** | Tap **Import from file** → select the downloaded key file |
   | **Public Key** | Leave empty |
   | **Passphrase** | Leave empty (key has no passphrase) |
   | **Certificate** | Leave empty |
3. Save

> **Alternative:** If you must paste, tap the Private Key field → paste → carefully verify the first line reads exactly `-----BEGIN OPENSSH PRIVATE KEY-----` and the last line reads exactly `-----END OPENSSH PRIVATE KEY-----` with no extra spaces or missing characters.

### Step 3: Create the host

1. Tap **+** → **New Host**
2. Fill in:
   | Field | Value |
   |-------|-------|
   | **Alias** | `Laptop` (or any name) |
   | **Hostname** | `<vps-ip>` |
   | **Port** | `2222` |
   | **Username** | `<your-laptop-username>` |
   | **Password** | Leave empty |
   | **Key** | Select `laptop-tunnel` from your keychain |

   > **Important:** Make sure the connection type is **SSH**, not Telnet or Mosh.

3. Save and tap the host to connect

### Step 4: Troubleshoot if it doesn't connect

| Symptom | Cause | Fix |
|---------|-------|-----|
| **Connection timeout** | VPS firewall blocking port 2222 | `ufw allow 2222/tcp` on VPS |
| **Connection timeout** | Tunnel not running on laptop | Check Task Scheduler, restart tunnel |
| **Connection timeout** | Phone on restricted WiFi | Switch to mobile data and retry |
| **Connection refused** | Port 2222 not bound (tunnel down) | `ss -tlnp \| grep 2222` on VPS — if empty, tunnel is down |
| **Permission denied** | Wrong key in Termius | Re-import key file, verify it's the VPS tunnel key (not the laptop key) |
| **Permission denied** | Key not in laptop's authorized_keys | Add VPS tunnel public key to `administrators_authorized_keys` |
| **Invalid key format** | Key was copy-pasted and corrupted | Re-import from file — never paste on iPhone |

### Connect from a desktop SSH client

```bash
ssh -p 2222 <user>@<vps-ip>
```

Works from any SSH client — PuTTY, Windows Terminal, macOS Terminal, Linux.

### Check tunnel status

```powershell
# View logs
Get-Content C:\Users\<user>\ssh-tunnel\tunnel.log -Tail 20

# Check if the task is running
Get-ScheduledTask -TaskName "SSH-Reverse-Tunnel" | Select TaskName, State

# Restart the tunnel
Restart-ScheduledTask -TaskName "SSH-Reverse-Tunnel"
```

### Verify from VPS

```bash
# Check if tunnel port is listening
ss -tlnp | grep 2222

# Test connection through tunnel
ssh -i ~/.ssh/id_tunnel -p 2222 user@localhost
```

---

## Security Considerations

| Layer | Protection |
|-------|-----------|
| **Authentication** | Public key only — no passwords |
| **Key separation** | Dedicated tunnel keypair (not reused for other access) |
| **Tunnel scope** | Only port 22 is forwarded (not a full VPN) |
| **Keepalive** | Dead connections detected in < 90 seconds |
| **Firewall** | VPS should restrict port 2222 to trusted source IPs if possible |
| **Encryption** | All traffic AES-256-GCM encrypted end-to-end via SSH |
| **No secrets in code** | All keys referenced by path, never embedded |

### Hardening recommendations

- Restrict VPS port 2222 to your known IPs via `ufw` / `iptables`
- Use `fail2ban` on the VPS for brute-force protection
- Rotate the tunnel keypair periodically
- Monitor `tunnel.log` for unexpected disconnects
- Consider adding MFA (TOTP) to the VPS SSH for interactive logins

---

## File Structure

```
laptop:
├── ~/.ssh/id_rsa                              # Key for laptop → VPS auth
├── ~/.bash_profile                            # Login shell config (aliases, welcome)
├── C:\ProgramData\ssh\administrators_authorized_keys  # Accepted keys for inbound SSH
└── ssh-tunnel/
    ├── tunnel.ps1                             # Tunnel loop with reconnection logic
    ├── install-service.ps1                    # Task Scheduler installer (run as admin)
    ├── keys/
    │   └── id_rsa                             # Copy of SSH key with SYSTEM-only perms
    ├── set-default-shell.ps1                  # Sets Git Bash as SSH default shell
    ├── shell.cmd                              # Wrapper to launch bash --login -i
    └── tunnel.log                             # Runtime logs (auto-rotated at 10MB)

vps:
├── ~/.ssh/authorized_keys                     # Accepted keys (with optional forced commands)
├── ~/.ssh/id_tunnel                           # Key for VPS → laptop auth
├── ~/.ssh/id_tunnel.pub
├── /etc/ssh/sshd_config.d/tunnel.conf         # Tunnel-specific SSH config
├── /root/phone-session.sh                     # Session persistence script
└── /root/.tmux.conf                           # Terminal multiplexer config
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection refused` on VPS:2222 | Tunnel not running | Check Task Scheduler status, review `tunnel.log` |
| `Permission denied` through tunnel | Key not in `administrators_authorized_keys` | Re-add VPS tunnel pubkey, restart `sshd` |
| Tunnel drops every few minutes | ISP or modem killing idle connections | `ServerAliveInterval=15` should prevent this; lower if needed |
| Tunnel up but port not bound | Previous tunnel still holding the port | Kill stale SSH processes on VPS: `pkill -f "sshd.*2222"` |
| High latency through tunnel | Double hop (you → VPS → laptop) | Expected — typically adds 20-50ms depending on VPS location |
| Task starts and immediately exits (code 1) | S4U logon type has no network credentials | Use SYSTEM principal (see `install-service.ps1`) |
| `UNPROTECTED PRIVATE KEY FILE` | Key permissions too open for SYSTEM | Run `install-service.ps1` — it copies the key with restricted ACLs |
| PowerShell parse error under Task Scheduler | Script has LF line endings or backtick continuations | Avoid backtick `\`` continuations; use splatting and ensure UTF-8 BOM encoding |
| Phone session dies when screen locks | No session persistence configured | Run `setup-phone-session.sh` and connect on port 22 (see Session Persistence) |

---

## Requirements

- **Laptop:** Windows 10/11 with OpenSSH Server capability
- **VPS:** Any Linux server with a public IP and SSH access
- **Network:** Any internet connection (works behind NAT, CGNAT, firewalls)

---

## License

MIT — see [LICENSE](LICENSE) for details.
