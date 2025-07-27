# Frontend Deployment Issues and Resolution

## Overview

This document chronicles the series of issues encountered during MetaMCP frontend deployment to Google Cloud Run and their systematic resolution. The deployment process revealed multiple interconnected problems related to monorepo dependency management, platform compatibility, and workspace command syntax.

## Timeline of Issues

### Initial Problem: "next is not found"

**Date**: July 27, 2025  
**Symptom**: 
```bash
sh: 1: next: not found
ELIFECYCLE Command failed.
WARN Local package.json exists, but node_modules missing, did you mean to install?
```

**Cloud Run Status**: Container failed to start and listen on port 12008

---

## Root Cause Analysis

### Issue #1: Dockerfile Dependency Management

**What was the issue?**

The original Dockerfile had a fundamental flaw in its production stage:

```dockerfile
# Install production dependencies only
RUN pnpm install --prod
```

**Why was this an issue?**

1. **Context Mismatch**: The command ran from `/app` (root directory) but the container started the application from `/app/apps/frontend`
2. **Monorepo Structure**: In a pnpm workspace setup, dependencies are managed at the root level with complex linking structures
3. **Binary Location**: The `next` binary was installed in `/app/node_modules/.pnpm/node_modules/.bin/` but not accessible from the frontend workspace context
4. **Workspace Dependencies**: The `--prod` flag didn't properly handle workspace dependencies and their binary linkage

### Issue #2: Incorrect pnpm Workspace Syntax

**What was the issue?**

The entrypoint script used incorrect pnpm workspace command syntax:

```bash
exec pnpm run start --filter=frontend  # ❌ WRONG
```

**Why was this an issue?**

1. **Syntax Error**: In pnpm workspaces, the `--filter` flag must come **before** the `run` command
2. **Command Failure**: This resulted in `ERR_PNPM_NO_SCRIPT_OR_SERVER Missing script start or file server.js`
3. **Workspace Context**: The incorrect syntax prevented pnpm from properly resolving the workspace context

### Issue #3: Platform Compatibility (QEMU Segmentation Fault)

**What was the issue?**

During the Docker build process:

```bash
frontend:build: qemu: uncaught target signal 11 (Segmentation fault) - core dumped
frontend:build: Next.js build worker exited with code: null and signal: SIGSEGV
```

**Why was this an issue?**

1. **Architecture Mismatch**: Building `--platform=linux/amd64` on Apple Silicon (ARM64) requires QEMU emulation
2. **Memory Intensive Process**: Next.js production builds are CPU and memory intensive
3. **QEMU Limitations**: QEMU emulation couldn't handle the complex build process, leading to segmentation faults
4. **Cross-Platform Building**: The heavy TypeScript compilation and bundling process was too demanding for emulation

### Issue #4: Exec Format Error

**What was the issue?**

After removing platform specification to avoid QEMU issues:

```bash
failed to load /app/apps/frontend/frontend-entrypoint.sh: exec format error
```

**Why was this an issue?**

1. **Architecture Mismatch**: Built ARM64 image when Cloud Run expects x86_64/amd64
2. **Runtime Incompatibility**: Cloud Run couldn't execute ARM64 binaries
3. **Platform Requirements**: Cloud Run infrastructure requires linux/amd64 containers

---

## Solutions Implemented

### Solution #1: Remove Problematic Dependency Installation

**What was changed:**

```dockerfile
# REMOVED: RUN pnpm install --prod

# KEPT: Copy built node_modules from builder stage
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./
COPY --from=builder --chown=nextjs:nodejs /app/pnpm-workspace.yaml ./

# Note: Dependencies already installed and copied from builder stage
# No need to reinstall since we need the full workspace setup for monorepo
```

**Why this fixed the issue:**

1. **Preserved Workspace Structure**: Maintained the complete monorepo dependency structure from build stage
2. **Binary Availability**: Kept all pnpm-managed binaries in their proper locations
3. **Workspace Integrity**: Preserved workspace linking and dependency resolution

### Solution #2: Fix pnpm Workspace Command Syntax

**What was changed:**

```bash
# BEFORE:
exec pnpm run start --filter=frontend

# AFTER:  
exec pnpm --filter=frontend run start
```

**Why this fixed the issue:**

1. **Correct Syntax**: Moved `--filter` flag to proper position before `run` command
2. **Workspace Resolution**: Allowed pnpm to correctly identify and execute the frontend workspace
3. **Command Success**: Enabled proper script execution from monorepo context

### Solution #3: Add PATH Configuration for Binaries

**What was changed:**

```bash
# Add pnpm binaries to PATH for monorepo setup
export PATH="/app/node_modules/.pnpm/node_modules/.bin:$PATH"
```

**Why this fixed the issue:**

1. **Binary Discovery**: Made `next` and other binaries discoverable from any directory
2. **Monorepo Compatibility**: Ensured workspace commands could find required tools
3. **Runtime Resolution**: Allowed the entrypoint script to execute commands regardless of working directory

### Solution #4: Platform-Aware Building Strategy

**What was changed:**

```bash
# Use environment variable to control platform building
DOCKER_DEFAULT_PLATFORM=linux/amd64 ./microservices_deploy/local-docker-deploy.sh
```

Combined with restoring platform specification in Dockerfile:

```dockerfile
FROM --platform=linux/amd64 ghcr.io/astral-sh/uv:debian AS base
```

**Why this fixed the issue:**

1. **Avoided QEMU Issues**: Environment variable approach bypassed QEMU segmentation faults
2. **Correct Target Platform**: Ensured final image was built for Cloud Run's expected architecture
3. **Build Stability**: Prevented emulation-related crashes during intensive build processes
4. **Runtime Compatibility**: Produced images that Cloud Run could execute natively

---

## Technical Details

### Monorepo Dependency Structure

In pnpm workspaces, dependencies are managed with a complex structure:

```
/app/
├── node_modules/
│   ├── .pnpm/
│   │   ├── node_modules/
│   │   │   └── .bin/          # ← Binary location
│   │   │       └── next       # ← The actual next binary
│   │   └── next@15.3.0_react-dom@19.1.0_react@19.1.0__react@19.1.0/
│   └── (symlinks and workspace structure)
├── apps/
│   └── frontend/
│       ├── package.json       # ← Contains "scripts": {"start": "next start"}
│       └── node_modules/      # ← Workspace-specific links
└── package.json               # ← Root workspace config
```

### Command Execution Flow

The corrected execution flow:

1. **Container starts** with `frontend-entrypoint.sh`
2. **PATH is set** to include `/app/node_modules/.pnpm/node_modules/.bin`
3. **pnpm command** executes from `/app` (root) with correct syntax
4. **Workspace resolution** finds frontend package and its scripts
5. **Binary execution** finds `next` in PATH and executes successfully

---

## Lessons Learned

### 1. Monorepo Dependency Management

- **Never reinstall dependencies** in production stage when using complex workspace setups
- **Preserve complete dependency structure** from build stage including all symbolic links
- **Understand pnpm workspace architecture** before modifying dependency installation

### 2. Cross-Platform Docker Building

- **QEMU limitations** can cause segmentation faults during intensive builds
- **Environment variables** can provide better platform control than dockerfile modifications alone
- **Build strategy matters** when targeting different architectures

### 3. Workspace Command Syntax

- **Flag ordering is critical** in pnpm workspace commands
- **Always test workspace commands** in isolation before using in production scripts
- **Understand tool-specific syntax** rather than assuming standard patterns

### 4. Container Platform Compatibility

- **Target platform must match runtime environment** (Cloud Run requires linux/amd64)
- **Architecture mismatches** manifest as "exec format error" at runtime
- **Build platform vs target platform** are different concerns

### 5. Debugging Methodology

- **Check logs systematically** from newest to oldest revisions
- **Isolate issues** by testing components individually
- **Document error messages precisely** for pattern recognition
- **Test fixes incrementally** rather than making multiple changes simultaneously

---

## Best Practices for Future Deployments

### Dockerfile Best Practices

1. **Always specify target platform** explicitly for production deployments
2. **Avoid reinstalling dependencies** in production stage for monorepos
3. **Copy complete dependency structures** when dealing with workspace setups
4. **Test builds locally** before pushing to deployment pipelines

### Entrypoint Script Best Practices

1. **Set appropriate PATH variables** for binary discovery
2. **Use correct workspace command syntax** for the specific package manager
3. **Test commands in isolation** before incorporating into scripts
4. **Add logging** for debugging deployment issues

### Platform Management Best Practices

1. **Use environment variables** to control build platforms when needed
2. **Test cross-platform builds** in development environments
3. **Understand target platform requirements** before building
4. **Document platform-specific workarounds** for team knowledge

### Debugging Best Practices

1. **Monitor deployment logs** immediately after deployment attempts
2. **Check multiple revision logs** to understand progression of issues
3. **Test container functionality locally** when possible
4. **Document all error messages and resolutions** for future reference

---

## Conclusion

The frontend deployment issues were caused by a combination of monorepo complexity, platform compatibility challenges, and workspace command syntax errors. The systematic resolution involved:

1. Understanding the pnpm workspace dependency structure
2. Fixing command syntax according to pnpm specifications  
3. Implementing platform-aware building strategies
4. Preserving monorepo integrity in the containerization process

This experience highlights the importance of understanding the underlying technologies (pnpm workspaces, Docker platform targeting, Cloud Run requirements) rather than treating them as black boxes. Each fix built upon the previous one, ultimately resulting in a successful deployment that serves the Next.js application correctly on Cloud Run.

**Final Result**: Frontend service successfully deployed and accessible at https://metamcp-frontend-pbxnxwryca-uc.a.run.app with 100% traffic routing to revision `metamcp-frontend-00025-4zs`.