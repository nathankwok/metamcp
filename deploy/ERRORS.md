# MetaMCP Error Resolution Guide

## Executive Summary

This document provides comprehensive analysis and resolution steps for three critical errors identified in the MetaMCP deployment on Google Compute Engine:

1. **502 Bad Gateway Errors** - HTTP client connection failures through nginx proxy
2. **Gemini CLI EACCES Permission Error** - Binary execution permission issues  
3. **Socket Hang Up on Port 12009** - TRPC connection failures and frontend service instability

These errors are preventing proper MCP server initialization and client connectivity, impacting the core functionality of the MetaMCP platform.

---

## Error 1: 502 Bad Gateway Issues

### Error Description
```
[MetaMCP][client] Error connecting to MetaMCP client (attempt 1/3) Error: Error POSTing to endpoint (HTTP 502): <html>
<head><title>502 Bad Gateway</title></head>
<body>
<center><h1>502 Bad Gateway</h1></center>
<hr><center>nginx/1.22.1</center>
</body>
</html>
```

### Root Cause Analysis
The 502 Bad Gateway error occurs when nginx successfully receives the client request but cannot get a valid response from the upstream backend service. This indicates:

- **Upstream Service Failure**: The backend service that nginx is proxying to is either crashed, unresponsive, or returning errors
- **Network Connectivity Issues**: Network problems between nginx and the backend service
- **Configuration Problems**: Incorrect upstream server definitions in nginx configuration
- **Resource Constraints**: Backend service may be overloaded or out of memory

### Impact
- MCP client connections fail repeatedly (attempts 1/3, 2/3, 3/3)
- Complete breakdown of HTTP-based MCP server communication
- Frontend unable to communicate with backend services
- User interface becomes non-functional

### Detailed Resolution Steps

#### 1. Diagnose Upstream Service Status
1. **SSH into the container**
   ```bash
   gcloud compute ssh metamcp-instance --zone=us-central1-a
   docker exec -it metamcp_production bash
   ```

2. **Check all running processes**
   ```bash
   ps aux | grep -E "(nginx|node|metamcp)"
   systemctl status nginx  # if using systemd
   ```

3. **Verify port listeners**
   ```bash
   netstat -tlnp | grep -E "(80|443|12008|12009)"
   ss -tlnp | grep -E "(80|443|12008|12009)"
   ```

#### 2. Examine Nginx Configuration
1. **Locate and review nginx config**
   ```bash
   find / -name "nginx.conf" -type f 2>/dev/null
   cat /etc/nginx/nginx.conf
   cat /etc/nginx/sites-enabled/default
   ```

2. **Check upstream definitions**
   ```bash
   grep -r "upstream" /etc/nginx/
   grep -r "proxy_pass" /etc/nginx/
   ```

3. **Review nginx error logs**
   ```bash
   tail -f /var/log/nginx/error.log
   tail -100 /var/log/nginx/error.log | grep -i "502\|upstream\|connect"
   ```

#### 3. Fix Backend Service Issues
1. **Restart crashed backend services**
   ```bash
   # If using PM2
   pm2 restart all
   pm2 status
   
   # If using direct node processes
   pkill -f "node.*metamcp"
   cd /app && npm start &
   ```

2. **Check service health endpoints**
   ```bash
   curl -I http://localhost:12008/health
   curl -I http://localhost:12009/health
   ```

3. **Verify database connectivity** (if applicable)
   ```bash
   # Test database connections that backend services depend on
   nc -zv localhost 5432  # PostgreSQL
   nc -zv localhost 6379  # Redis
   ```

#### 4. Fix Nginx Configuration
1. **Update upstream server definitions**
   ```nginx
   upstream metamcp_backend {
       server localhost:12008 max_fails=3 fail_timeout=30s;
       server localhost:12009 max_fails=3 fail_timeout=30s;
   }
   ```

2. **Add proper health checks**
   ```nginx
   location /health {
       proxy_pass http://metamcp_backend/health;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```

3. **Reload nginx configuration**
   ```bash
   nginx -t  # Test configuration
   nginx -s reload  # Reload if test passes
   ```

---

## Error 2: Gemini CLI EACCES Permission Error

### Error Description
```
[MetaMCP][gemini-cli] [GMCPT] Process error:
 Error: spawn gemini EACCES
    at ChildProcess._handle.onexit (node:internal/child_process:285:19) {
  errno: -13,
  code: 'EACCES',
  syscall: 'spawn gemini',
  path: 'gemini',
  spawnargs: ['-p', "Search for revefi and snowflake documentation..."]
}
```

### Root Cause Analysis
The EACCES (Permission Denied) error when spawning the `gemini` command indicates:

- **Binary Not Found**: The `gemini` executable is not in the system PATH
- **Permission Issues**: The `gemini` binary exists but lacks execute permissions
- **Installation Problems**: Gemini CLI was not properly installed in the Docker container
- **User Permission Issues**: The process user doesn't have permission to execute the binary

### Impact
- Gemini MCP server functionality completely broken
- AI-powered search and documentation features unavailable
- MCP tool `ask-gemini` fails for all requests
- Reduced overall platform capabilities

### Detailed Resolution Steps

#### 1. Diagnose Gemini CLI Installation
1. **Check if gemini binary exists**
   ```bash
   which gemini
   whereis gemini
   find / -name "gemini" -type f 2>/dev/null
   ```

2. **Check PATH environment**
   ```bash
   echo $PATH
   ls -la /usr/local/bin/ | grep gemini
   ls -la /usr/bin/ | grep gemini
   ```

3. **Verify current user permissions**
   ```bash
   whoami
   id
   groups
   ```

#### 2. Install Gemini CLI Properly
1. **Install Google's Gemini CLI**
   ```bash
   # Method 1: Using npm (recommended)
   npm install -g @google/generative-ai-cli
   
   # Method 2: Direct download
   curl -sSL https://install.gemini.google.com | bash
   ```

2. **Verify installation**
   ```bash
   gemini --version
   gemini --help
   ```

3. **Set up authentication**
   ```bash
   # Set API key environment variable
   export GEMINI_API_KEY="your-api-key-here"
   # Or configure via gemini CLI
   gemini config set api-key "your-api-key-here"
   ```

#### 3. Fix File Permissions
1. **Make binary executable**
   ```bash
   chmod +x $(which gemini)
   # Or if in specific location
   chmod +x /usr/local/bin/gemini
   ```

2. **Fix ownership if needed**
   ```bash
   chown $(whoami):$(whoami) $(which gemini)
   ```

3. **Update PATH in shell profile**
   ```bash
   echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

#### 4. Test Gemini CLI Functionality
1. **Basic command test**
   ```bash
   gemini --version
   gemini config list
   ```

2. **Test with simple prompt**
   ```bash
   gemini -p "Hello, test message"
   ```

3. **Verify MCP integration**
   ```bash
   # Restart MCP services to pick up fixed gemini
   pm2 restart gemini-cli
   # Or restart entire application
   pm2 restart all
   ```

---

## Error 3: Socket Hang Up on Port 12009

### Error Description
```
Failed to proxy http://localhost:12009/trpc/frontend/frontend.logs.get?batch=1&input=%7B%220%22%3A%7B%22limit%22%3A500%7D%7D [Error: socket hang up] { code: 'ECONNRESET' }
```

### Root Cause Analysis
Socket hang up errors (ECONNRESET) on port 12009 indicate:

- **Frontend Service Crashes**: The service on port 12009 is crashing or restarting
- **Connection Timeouts**: Requests are timing out due to slow responses
- **Resource Exhaustion**: Service running out of memory or CPU
- **Network Issues**: TCP connection being reset by the peer
- **Application Bugs**: Unhandled exceptions causing connection drops

### Impact
- Frontend logging functionality broken
- TRPC communication failures between frontend and backend
- User interface may become partially or completely unresponsive
- Loss of real-time application monitoring capabilities

### Detailed Resolution Steps

#### 1. Diagnose Frontend Service Status
1. **Check service on port 12009**
   ```bash
   netstat -tlnp | grep 12009
   ss -tlnp | grep 12009
   lsof -i :12009
   ```

2. **Test direct connection**
   ```bash
   curl -v http://localhost:12009/health
   curl -v http://localhost:12009/trpc/frontend/frontend.logs.get
   telnet localhost 12009
   ```

3. **Check process status**
   ```bash
   ps aux | grep -E "(node.*12009|frontend|trpc)"
   pgrep -f "port.*12009"
   ```

#### 2. Examine Application Logs
1. **Check application-specific logs**
   ```bash
   # If using PM2
   pm2 logs frontend
   pm2 logs | grep -i "12009\|trpc\|frontend"
   
   # If using direct logging
   tail -f /app/logs/frontend.log
   tail -f /app/logs/application.log | grep -E "(12009|ECONNRESET|socket)"
   ```

2. **Look for memory/resource issues**
   ```bash
   free -h
   df -h
   top -p $(pgrep -f "port.*12009")
   ```

3. **Check for unhandled exceptions**
   ```bash
   grep -i "unhandled\|exception\|error" /app/logs/*.log | tail -20
   ```

#### 3. Fix Service Connectivity Issues
1. **Restart frontend service**
   ```bash
   # If using PM2
   pm2 restart frontend
   pm2 restart all
   
   # If using systemd
   systemctl restart metamcp-frontend
   
   # If using direct node process
   pkill -f "node.*12009"
   cd /app && PORT=12009 npm run start:frontend &
   ```

2. **Increase timeout values**
   ```javascript
   // In application config
   const server = app.listen(12009, {
     timeout: 60000, // 60 seconds
     keepAliveTimeout: 65000,
     headersTimeout: 66000
   });
   ```

3. **Add connection retry logic**
   ```javascript
   // In TRPC client configuration
   const trpcClient = createTRPCProxyClient({
     links: [
       httpBatchLink({
         url: 'http://localhost:12009/trpc',
         fetch: (url, options) => {
           return fetch(url, {
             ...options,
             timeout: 30000,
             retry: 3
           });
         }
       })
     ]
   });
   ```

#### 4. Implement Health Monitoring
1. **Add health check endpoint**
   ```javascript
   app.get('/health', (req, res) => {
     res.status(200).json({
       status: 'healthy',
       timestamp: new Date().toISOString(),
       uptime: process.uptime(),
       memory: process.memoryUsage()
     });
   });
   ```

2. **Add process monitoring**
   ```bash
   # Create monitoring script
   cat > /app/monitor_frontend.sh << 'EOF'
   #!/bin/bash
   while true; do
     if ! curl -f http://localhost:12009/health > /dev/null 2>&1; then
       echo "Frontend service down, restarting..."
       pm2 restart frontend
     fi
     sleep 30
   done
   EOF
   chmod +x /app/monitor_frontend.sh
   ```

---

## Implementation Phases

### Phase 1: Immediate Diagnostics (Priority: Critical)

#### 1.1 Container Access and Initial Assessment
1. **SSH into Compute Engine instance**
   ```bash
   gcloud compute ssh metamcp-instance --zone=us-central1-a
   ```

2. **Access running container**
   ```bash
   docker exec -it metamcp_production bash
   ```

3. **Check overall system health**
   ```bash
   free -h && df -h && uptime
   ```

#### 1.2 Service Status Verification
1. **List all running processes**
   ```bash
   ps aux | head -20
   ps aux | grep -E "(nginx|node|gemini|metamcp)"
   ```

2. **Check port bindings**
   ```bash
   netstat -tlnp | grep -E "(80|443|12008|12009)"
   ```

3. **Verify Docker container health**
   ```bash
   exit  # Exit container
   docker ps -a
   docker inspect metamcp_production | grep -A 10 -B 10 "Health"
   ```

#### 1.3 Log Analysis Deep Dive
1. **Collect recent application logs**
   ```bash
   docker logs metamcp_production --tail=100 > /tmp/recent_logs.txt
   ```

2. **Search for specific error patterns**
   ```bash
   grep -E "(502|EACCES|ECONNRESET)" /tmp/recent_logs.txt
   ```

3. **Identify error frequency and timing**
   ```bash
   grep -E "(502|EACCES|ECONNRESET)" /tmp/recent_logs.txt | cut -d' ' -f1-3 | sort | uniq -c
   ```

### Phase 2: Quick Fixes (Priority: High)

#### 2.1 Fix Gemini CLI Issues
1. **Install Gemini CLI globally**
   ```bash
   docker exec -it metamcp_production bash
   npm install -g @google/generative-ai-cli
   ```

2. **Set proper permissions**
   ```bash
   chmod +x $(which gemini)
   gemini --version  # Verify installation
   ```

3. **Configure authentication**
   ```bash
   export GEMINI_API_KEY="${GEMINI_API_KEY}"
   echo 'export GEMINI_API_KEY="${GEMINI_API_KEY}"' >> ~/.bashrc
   ```

#### 2.2 Restart Critical Services
1. **Restart nginx (if running)**
   ```bash
   service nginx restart || systemctl restart nginx
   ```

2. **Restart Node.js applications**
   ```bash
   pm2 restart all || npm run restart
   ```

3. **Verify service startup**
   ```bash
   sleep 10
   curl -I http://localhost:12008/health
   curl -I http://localhost:12009/health
   ```

#### 2.3 Test Immediate Connectivity
1. **Test internal service communication**
   ```bash
   curl -v http://localhost:12009/trpc/frontend/frontend.logs.get
   ```

2. **Verify MCP server initialization**
   ```bash
   docker logs metamcp_production --tail=20 | grep -E "(Created|Saved|Available)"
   ```

### Phase 3: Long-term Stability Improvements (Priority: Medium)

#### 3.1 Update Container Configuration
1. **Review and update Dockerfile**
   ```dockerfile
   # Add proper Gemini CLI installation
   RUN npm install -g @google/generative-ai-cli && \
       chmod +x $(which gemini) && \
       gemini --version
   
   # Add health checks
   HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
       CMD curl -f http://localhost:12008/health && curl -f http://localhost:12009/health || exit 1
   ```

2. **Add monitoring and logging improvements**
   ```dockerfile
   # Install monitoring tools
   RUN apt-get update && apt-get install -y \
       htop \
       curl \
       netstat-nat \
       && rm -rf /var/lib/apt/lists/*
   ```

#### 3.2 Implement Service Resilience
1. **Add automatic restart configuration**
   ```javascript
   // In PM2 ecosystem file
   module.exports = {
     apps: [{
       name: 'metamcp-frontend',
       script: './dist/frontend.js',
       port: 12009,
       max_restarts: 10,
       min_uptime: '10s',
       max_memory_restart: '500M'
     }]
   };
   ```

2. **Add connection retry logic**
   ```javascript
   // In application connection handling
   const retryConnection = async (fn, maxRetries = 3) => {
     for (let i = 0; i < maxRetries; i++) {
       try {
         return await fn();
       } catch (error) {
         if (i === maxRetries - 1) throw error;
         await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, i)));
       }
     }
   };
   ```

#### 3.3 Enhanced Error Handling
1. **Add comprehensive error logging**
   ```javascript
   process.on('uncaughtException', (error) => {
     console.error('Uncaught Exception:', error);
     // Graceful shutdown logic
   });
   
   process.on('unhandledRejection', (reason, promise) => {
     console.error('Unhandled Rejection at:', promise, 'reason:', reason);
   });
   ```

2. **Implement circuit breaker pattern**
   ```javascript
   class CircuitBreaker {
     constructor(threshold = 5, timeout = 60000) {
       this.threshold = threshold;
       this.timeout = timeout;
       this.failureCount = 0;
       this.state = 'CLOSED';
       this.nextAttempt = Date.now();
     }
     
     async call(fn) {
       if (this.state === 'OPEN') {
         if (Date.now() < this.nextAttempt) {
           throw new Error('Circuit breaker is OPEN');
         }
         this.state = 'HALF_OPEN';
       }
       
       try {
         const result = await fn();
         this.onSuccess();
         return result;
       } catch (error) {
         this.onFailure();
         throw error;
       }
     }
   }
   ```

### Phase 4: Testing and Validation (Priority: Low)

#### 4.1 Comprehensive Service Testing
1. **Test all MCP server connections**
   ```bash
   # Test each MCP server individually
   curl -X POST http://localhost:12008/mcp/gemini-cli/tools
   curl -X POST http://localhost:12008/mcp/context7/tools
   curl -X POST http://localhost:12008/mcp/supabase/tools
   ```

2. **Load test critical endpoints**
   ```bash
   # Install Apache Bench for load testing
   apt-get install apache2-utils
   
   # Test frontend endpoint
   ab -n 100 -c 10 http://localhost:12009/health
   
   # Test backend endpoint
   ab -n 100 -c 10 http://localhost:12008/health
   ```

#### 4.2 Monitor System Stability
1. **Set up continuous monitoring**
   ```bash
   # Create monitoring script
   cat > /app/health_monitor.sh << 'EOF'
   #!/bin/bash
   while true; do
     echo "$(date): Checking service health..."
     
     # Check Gemini CLI
     if ! gemini --version > /dev/null 2>&1; then
       echo "ALERT: Gemini CLI not working"
     fi
     
     # Check port 12008
     if ! curl -f http://localhost:12008/health > /dev/null 2>&1; then
       echo "ALERT: Port 12008 service down"
     fi
     
     # Check port 12009
     if ! curl -f http://localhost:12009/health > /dev/null 2>&1; then
       echo "ALERT: Port 12009 service down"
     fi
     
     sleep 60
   done
   EOF
   chmod +x /app/health_monitor.sh
   ```

2. **Log performance metrics**
   ```bash
   # Create performance logging
   cat > /app/perf_monitor.sh << 'EOF'
   #!/bin/bash
   while true; do
     echo "$(date): $(free -h | grep Mem) | $(df -h / | tail -1)" >> /app/logs/performance.log
     sleep 300  # Every 5 minutes
   done
   EOF
   chmod +x /app/perf_monitor.sh
   ```

#### 4.3 Validation Checklist
- [ ] All three error types resolved
- [ ] Gemini CLI working and accessible
- [ ] Frontend service stable on port 12009
- [ ] Backend service responding on port 12008
- [ ] MCP servers initializing successfully
- [ ] No 502 errors in nginx logs
- [ ] No socket hang up errors in application logs
- [ ] Health checks passing consistently
- [ ] Performance metrics within acceptable ranges
- [ ] Error monitoring and alerting functional

---

## Summary

This comprehensive guide addresses the three critical errors affecting MetaMCP deployment:

1. **502 Bad Gateway** - Resolved through nginx configuration fixes and upstream service restarts
2. **Gemini CLI EACCES** - Fixed via proper installation and permission configuration  
3. **Socket Hang Up** - Addressed through service restart and connection resilience improvements

Following this phase-by-phase approach ensures systematic resolution while building long-term stability into the MetaMCP platform.