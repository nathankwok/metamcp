# Terragon - Google Cloud Setup and Testing Suite

A comprehensive toolkit for setting up and testing Google Cloud service accounts, CLI tools, and authentication for deployment workflows.

## Overview

The Terragon suite consists of three interconnected scripts that provide a complete Google Cloud setup and validation workflow:

1. **`setup-service-account.sh`** - Creates and configures Google Cloud service accounts
2. **`test-service-account.sh`** - Tests service account permissions and connectivity  
3. **`../terragon-setup.sh`** - Installs CLI tools and sets up development environment

## Scripts

### 1. setup-service-account.sh

**Purpose**: Creates a Google Cloud service account with all necessary permissions for deployment operations.

**What it does**:
- Creates a service account named `terragon-deploy`
- Enables required Google Cloud APIs:
  - Cloud Build API
  - Cloud Run API  
  - Artifact Registry API
  - Secret Manager API
  - IAM API
- Grants comprehensive IAM roles:
  - `roles/cloudbuild.builds.builder` - Cloud Build operations
  - `roles/run.admin` - Cloud Run deployments
  - `roles/artifactregistry.writer` - Container image management
  - `roles/secretmanager.secretVersionAdder` - Secret creation
  - `roles/secretmanager.secretAccessor` - Secret access
  - `roles/iam.serviceAccountUser` - Service account usage
  - `roles/storage.admin` - Cloud Build artifacts
  - `roles/compute.viewer` - Cloud Run deployment requirements
- Generates and downloads service account key file (`terragon-service-account-key.json`)

**Prerequisites**:
- Authenticated with `gcloud auth login`
- Project set with `gcloud config set project PROJECT_ID`
- Owner or Editor permissions on the Google Cloud project

**Usage**:
```bash
# Use current gcloud project
./setup-service-account.sh

# Specify project via environment variable
PROJECT_ID=your-project-id ./setup-service-account.sh
```

**Output**:
- Service account key file: `terragon-service-account-key.json`
- Detailed setup summary with authentication instructions

### 2. test-service-account.sh

**Purpose**: Comprehensive testing suite that validates service account permissions and connectivity.

**What it does**:
- Installs Google Cloud CLI (if needed) with minimal components
- Authenticates using service account key
- Tests all required Google Cloud service permissions:
  - Cloud Build (list builds, repositories)
  - Cloud Run (list regions, services)
  - Artifact Registry (list locations, repositories)
  - Secret Manager (list/create/delete secrets)
  - Storage (list buckets)
  - Compute Engine (list zones)
  - IAM (list service accounts)
- Validates API enablement status
- Configures Docker credential helper
- Runs extended tests in non-minimal mode

**Configuration Options**:
```bash
# Environment variables
INSTALL_GCLOUD="auto|yes|no"          # Auto-install gcloud CLI
MINIMAL_INSTALL="true|false"          # Install minimal components only
PARALLEL_OPERATIONS="true|false"      # Run tests in parallel
DEBUG_OUTPUT="true|false"             # Show detailed error output
ENABLE_APIS="true|false"               # Auto-enable missing APIs
SERVICE_ACCOUNT_KEY_JSON="..."        # JSON key content
SERVICE_ACCOUNT_KEY_FILE="path"       # Path to key file
```

**Usage**:
```bash
# Basic usage with existing key file
./test-service-account.sh

# Fast mode (default)
PARALLEL_OPERATIONS=true MINIMAL_INSTALL=true ./test-service-account.sh

# Comprehensive testing
MINIMAL_INSTALL=false ./test-service-account.sh

# Auto-enable APIs if missing
ENABLE_APIS=true ./test-service-account.sh

# Use key from environment variable
SERVICE_ACCOUNT_KEY_JSON='{"type":"service_account",...}' ./test-service-account.sh
```

**Exit Codes**:
- `0` - All tests passed
- `1` - Some tests failed or warnings
- `2` - Critical failures (authentication, setup issues)

### 3. ../terragon-setup.sh

**Purpose**: Development environment setup with Google Cloud CLI and Gemini CLI installation.

**What it does**:
- Installs Google Cloud CLI (minimal mode by default)
- Installs Google Gemini CLI via npm (`@google/generative-ai`)
- Sets up service account authentication
- Configures Docker credential helper
- Automatically detects and installs system dependencies:
  - curl, python3, Node.js, npm

**Configuration Options**:
```bash
INSTALL_GCLOUD="auto|yes|no"          # Auto-install gcloud CLI
INSTALL_GEMINI_CLI="auto|yes|no"      # Auto-install Gemini CLI
MINIMAL_INSTALL="true|false"          # Minimal gcloud installation
DEBUG_OUTPUT="true|false"             # Show detailed output
ENABLE_APIS="true|false"               # Auto-enable APIs
```

**Usage**:
```bash
# Basic setup with auto-installation
./terragon-setup.sh

# Skip Gemini CLI installation
INSTALL_GEMINI_CLI=no ./terragon-setup.sh

# Full gcloud installation
MINIMAL_INSTALL=false ./terragon-setup.sh
```

## Complete Workflow

### Initial Setup (One-time)

1. **Create Service Account**:
   ```bash
   cd terragon/
   ./setup-service-account.sh
   ```
   
2. **Verify Setup**:
   ```bash
   ./test-service-account.sh
   ```

### Development Environment Setup

3. **Install CLI Tools**:
   ```bash
   cd ..
   ./terragon-setup.sh
   ```

### Ongoing Usage

- **Re-test permissions**: Run `test-service-account.sh` anytime
- **Update environment**: Re-run `terragon-setup.sh` for CLI updates
- **Rotate keys**: Re-run `setup-service-account.sh` to generate new keys

## File Structure

```
terragon/
├── README.md                          # This file
├── setup-service-account.sh           # Service account creation
├── test-service-account.sh            # Permission testing
├── terragon-service-account-key.json  # Generated service account key
└── ../terragon-setup.sh               # Environment setup
```

## Security Notes

- **Key File Security**: The `terragon-service-account-key.json` file contains sensitive credentials
- **Never commit keys**: Add `*.json` to `.gitignore`
- **Key rotation**: Regularly rotate service account keys
- **Minimal permissions**: Scripts grant only necessary permissions
- **Workload Identity**: Consider using Workload Identity instead of key files for production

## Troubleshooting

### Common Issues

1. **Authentication Errors**:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Permission Denied**:
   - Ensure you have Owner/Editor role on the project
   - Check that required APIs are enabled

3. **Key File Not Found**:
   ```bash
   # Specify key file location
   SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json ./test-service-account.sh
   ```

4. **API Not Enabled**:
   ```bash
   # Auto-enable APIs
   ENABLE_APIS=true ./test-service-account.sh
   ```

### Debug Mode

Enable verbose output for troubleshooting:
```bash
DEBUG_OUTPUT=true ./test-service-account.sh
```

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_ID` | Auto-detected | Google Cloud project ID |
| `SERVICE_ACCOUNT_NAME` | `terragon-deploy` | Service account name |
| `SERVICE_ACCOUNT_KEY_FILE` | `terragon-service-account-key.json` | Key file path |
| `SERVICE_ACCOUNT_KEY_JSON` | - | Key content as JSON string |
| `INSTALL_GCLOUD` | `auto` | Install gcloud CLI |
| `INSTALL_GEMINI_CLI` | `auto` | Install Gemini CLI |
| `MINIMAL_INSTALL` | `true` | Minimal gcloud installation |
| `PARALLEL_OPERATIONS` | `true` | Run tests in parallel |
| `DEBUG_OUTPUT` | `false` | Show debug information |
| `ENABLE_APIS` | `true` | Auto-enable missing APIs |

## Example Usage Scenarios

### CI/CD Pipeline Setup
```bash
# In CI environment
export SERVICE_ACCOUNT_KEY_JSON="${GOOGLE_CREDENTIALS}"
export MINIMAL_INSTALL=true
export PARALLEL_OPERATIONS=true
./terragon-setup.sh && ./terragon/test-service-account.sh
```

### Local Development
```bash
# One-time setup
./terragon/setup-service-account.sh
./terragon-setup.sh

# Verify periodically
./terragon/test-service-account.sh
```

### Production Deployment Validation
```bash
# Comprehensive testing before deployment
MINIMAL_INSTALL=false ENABLE_APIS=true ./terragon/test-service-account.sh
```

---

For issues or questions, check the script output and exit codes for detailed error information.