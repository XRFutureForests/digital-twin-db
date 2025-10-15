# WSL2 Supabase Access Guide

## ✅ Supabase is Running Successfully in WSL2!

The services are all working, but you need to access them properly from Windows.

## 🌐 How to Access from Windows Browser

### Option 1: Using localhost (Recommended)

WSL2 automatically forwards `localhost` ports to Windows. Open your **Windows browser** (Chrome, Edge, Firefox) and go to:

```
http://localhost:54323
```

This should open Supabase Studio.

**If this doesn't work**, it means Windows firewall or WSL2 networking needs configuration. Try Option 2.

### Option 2: Using WSL2 IP Address

Your WSL2 IP address is: **172.17.200.223**

Try accessing from Windows browser:
```
http://172.17.200.223:54323
```

### Option 3: Port Forwarding (If localhost doesn't work)

If neither option works, you need to add a port forwarding rule in Windows PowerShell (Run as Administrator):

```powershell
# Forward port 54323 (Studio)
netsh interface portproxy add v4tov4 listenport=54323 listenaddress=0.0.0.0 connectport=54323 connectaddress=172.17.200.223

# Forward port 54321 (API Gateway)
netsh interface portproxy add v4tov4 listenport=54321 listenaddress=0.0.0.0 connectport=54321 connectaddress=172.17.200.223

# Forward port 54322 (Database)
netsh interface portproxy add v4tov4 listenport=54322 listenaddress=0.0.0.0 connectport=54322 connectaddress=172.17.200.223
```

To check current port forwards:
```powershell
netsh interface portproxy show all
```

To remove port forwards (if needed):
```powershell
netsh interface portproxy delete v4tov4 listenport=54323 listenaddress=0.0.0.0
netsh interface portproxy delete v4tov4 listenport=54321 listenaddress=0.0.0.0
netsh interface portproxy delete v4tov4 listenport=54322 listenaddress=0.0.0.0
```

## 🔥 Windows Firewall

If you still can't connect, you may need to allow the ports in Windows Firewall:

```powershell
# Run in PowerShell as Administrator
New-NetFirewallRule -DisplayName "WSL2 Supabase Studio" -Direction Inbound -LocalPort 54323 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 Supabase API" -Direction Inbound -LocalPort 54321 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "WSL2 PostgreSQL" -Direction Inbound -LocalPort 54322 -Protocol TCP -Action Allow
```

## 📊 Service URLs

Once accessible, use these URLs from Windows:

| Service | URL | Purpose |
|---------|-----|---------|
| **Supabase Studio** | http://localhost:54323 | Web UI for database management |
| **API Gateway (Kong)** | http://localhost:54321 | REST API endpoint |
| **PostgreSQL Database** | localhost:54322 | Direct database connection |

## 🔑 Credentials

### Supabase Studio
- No login required for local development

### PostgreSQL Database
```
Host: localhost
Port: 54322
Username: postgres
Password: postgres
Database: postgres
```

### API Keys (for REST API)
```bash
# Anonymous Key (public, for client apps)
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzYwNTE3MzI3LCJleHAiOjIwNzU4NzczMjd9.lIi-KdAxFeBpXYR5jdKJA-vJfZ0eL9y0n7Lx4mUYNv8

# Service Role Key (secret, server-side only)
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3NjA1MTczMjcsImV4cCI6MjA3NTg3NzMyN30.SBbtSD8usWyQNSuOZYPFLdJ0SJh2i77fUMLZkeA0DDc
```

## ✅ Testing from WSL2 Terminal

To verify services are running from within WSL2:

```bash
# Test Studio
curl http://localhost:54323

# Test API Gateway
curl http://localhost:54321

# Test Database
docker exec xr_forests_db psql -U postgres -c "SELECT version();"
```

## 🐛 Troubleshooting

### "Connection refused" from Windows
- Check if Docker Desktop is running with WSL2 integration enabled
- Try restarting WSL2: `wsl --shutdown` from Windows PowerShell, then restart
- Verify services are running: `docker compose ps`

### "This site can't be reached" in browser
- Make sure you're using `http://` not `https://`
- Check Windows Firewall settings
- Try the WSL2 IP address directly: http://172.17.200.223:54323

### Studio shows "unhealthy" but responds
- This is normal - Studio takes time to fully initialize
- As long as you can access it in browser, it's working

### Port forwarding stops after Windows restart
- Port proxy rules persist but you need to update the WSL2 IP if it changes
- Get new IP: `wsl hostname -I` from PowerShell
- Update portproxy rules with new IP

## 🚀 Quick Start Commands

### Start Supabase
```bash
cd ~/git/digital-twin
docker compose up -d
```

### Stop Supabase
```bash
docker compose down
```

### View logs
```bash
docker compose logs -f
```

### Restart a service
```bash
docker compose restart studio
```

## 📱 Access from Mobile/Other Devices

To access from other devices on your network:

1. Find your Windows PC's IP address: `ipconfig` in Windows CMD
2. Use that IP with the port: `http://<WINDOWS-IP>:54323`
3. Make sure Windows Firewall allows inbound connections on these ports

## 🔗 Useful Links

- Supabase Documentation: https://supabase.com/docs
- PostgREST API Reference: https://postgrest.org/
- Docker Compose Docs: https://docs.docker.com/compose/

---

**Note**: Your WSL2 IP (172.17.200.223) may change after rebooting. Always check with `hostname -I` if you have connection issues.
