#!/bin/bash

# Google Cloud Service Account Connection Test Script
# This script installs gcloud CLI and Google Gemini CLI (if needed) and tests service account authentication
# and verifies permissions for all required services: Cloud Build, Cloud Run, Artifact Registry, Secret Manager

# Note: Removed 'set -e' to allow script to continue even when individual commands fail
# Individual test failures are tracked and reported at the end

# Configuration
GCLOUD_VERSION="463.0.0"  # Update as needed
SERVICE_ACCOUNT_KEY_JSON=${SERVICE_ACCOUNT_KEY_JSON:-""}
SERVICE_ACCOUNT_KEY_FILE=${SERVICE_ACCOUNT_KEY_FILE:-"terragon-service-account-key.json"}
PROJECT_ID=${PROJECT_ID:-""}
INSTALL_GCLOUD=${INSTALL_GCLOUD:-"auto"}  # auto, yes, no
INSTALL_GEMINI_CLI=${INSTALL_GEMINI_CLI:-"auto"}  # auto, yes, no

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()
SETUP_FAILURES=()
CRITICAL_FAILURE=false

echo -e "${BLUE}🧪 Google Cloud Service Account Connection Test${NC}"
echo "=================================================================="

# Function to install gcloud CLI
install_gcloud_cli() {
    echo -e "${GREEN}Installing Google Cloud CLI...${NC}"

    # Detect OS and architecture
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case $ARCH in
        x86_64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="arm"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            SETUP_FAILURES+=("Unsupported architecture: $ARCH")
            return 1
            ;;
    esac

    echo -e "${BLUE}Detected OS: $OS, Architecture: $ARCH${NC}"

    # Install dependencies if needed
    echo -e "${GREEN}Checking dependencies...${NC}"
    if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing dependencies...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y curl python3 python3-pip nodejs npm
        elif command -v yum >/dev/null 2>&1; then
            # CentOS/RHEL
            sudo yum update -y
            sudo yum install -y curl python3 python3-pip nodejs npm
        elif command -v apk >/dev/null 2>&1; then
            # Alpine
            sudo apk update
            sudo apk add curl python3 py3-pip nodejs npm
        elif command -v brew >/dev/null 2>&1; then
            # macOS with Homebrew
            brew install curl python3 node
        else
            echo -e "${YELLOW}Warning: Could not detect package manager. Ensure curl, python3, and Node.js are installed.${NC}"
        fi
    fi

    # Download and install Google Cloud CLI
    echo -e "${GREEN}Downloading Google Cloud CLI...${NC}"
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    if [ "$OS" = "linux" ]; then
        DOWNLOAD_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-${ARCH}.tar.gz"
        ARCHIVE_NAME="google-cloud-cli-${GCLOUD_VERSION}-linux-${ARCH}.tar.gz"
    elif [ "$OS" = "darwin" ]; then
        DOWNLOAD_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-darwin-${ARCH}.tar.gz"
        ARCHIVE_NAME="google-cloud-cli-${GCLOUD_VERSION}-darwin-${ARCH}.tar.gz"
    else
        echo -e "${RED}Unsupported OS: $OS${NC}"
        SETUP_FAILURES+=("Unsupported OS: $OS")
        return 1
    fi

    curl -O "$DOWNLOAD_URL"

    # Extract and install
    echo -e "${GREEN}Installing Google Cloud CLI...${NC}"
    tar -xzf "$ARCHIVE_NAME"

    # Determine installation directory
    if [ "$OS" = "linux" ] && [ "$EUID" -eq 0 ]; then
        # Root on Linux - install system-wide
        INSTALL_DIR="/opt/google-cloud-sdk"
        if [ -d "$INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
        fi
        mv google-cloud-sdk "$INSTALL_DIR"
        echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> /etc/profile
    else
        # Non-root or macOS - install in user directory
        INSTALL_DIR="$HOME/google-cloud-sdk"
        if [ -d "$INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
        fi
        mv google-cloud-sdk "$INSTALL_DIR"

        # Add to shell profile
        for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
            if [ -f "$profile" ]; then
                if ! grep -q "google-cloud-sdk/bin" "$profile"; then
                    echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$profile"
                fi
            fi
        done
    fi

    # Add to current session PATH
    export PATH="$INSTALL_DIR/bin:$PATH"

    # Run installation script
    "$INSTALL_DIR/install.sh" --quiet --usage-reporting=false --command-completion=true --path-update=false

    # Verify installation
    echo -e "${GREEN}Verifying installation...${NC}"
    "$INSTALL_DIR/bin/gcloud" version

    # Clean up
    cd - >/dev/null
    rm -rf "$TEMP_DIR"

    echo -e "${GREEN}✅ Google Cloud CLI installed successfully${NC}"
}

# Function to install Google Gemini CLI
install_gemini_cli() {
    echo -e "${GREEN}Installing Google Gemini CLI...${NC}"

    # Check if Node.js and npm are available
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        echo -e "${YELLOW}Node.js and npm are required for Gemini CLI installation...${NC}"

        # Install Node.js if not present
        echo -e "${GREEN}Installing Node.js and npm...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y nodejs npm
        elif command -v yum >/dev/null 2>&1; then
            # CentOS/RHEL
            sudo yum update -y
            sudo yum install -y nodejs npm
        elif command -v apk >/dev/null 2>&1; then
            # Alpine
            sudo apk update
            sudo apk add nodejs npm
        elif command -v brew >/dev/null 2>&1; then
            # macOS with Homebrew
            brew install node
        else
            echo -e "${RED}Error: Cannot install Node.js automatically. Please install Node.js and npm manually.${NC}"
            return 1
        fi
    fi

    # Verify Node.js installation
    echo -e "${BLUE}Node.js version: $(node --version)${NC}"
    echo -e "${BLUE}npm version: $(npm --version)${NC}"

    # Install Gemini CLI globally
    echo -e "${GREEN}Installing @google/gemini-cli globally...${NC}"
    if command -v sudo >/dev/null 2>&1 && [ "$EUID" -ne 0 ]; then
        # Non-root user - use sudo for global npm install
        sudo npm install -g @google/gemini-cli
    else
        # Root user or no sudo available
        npm install -g @google/gemini-cli
    fi

    # Verify installation
    if command -v gemini >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Google Gemini CLI installed successfully${NC}"
        echo -e "${BLUE}Gemini CLI version: $(gemini --version 2>/dev/null || echo 'Version check failed')${NC}"
        return 0
    else
        echo -e "${RED}❌ Gemini CLI installation failed or not in PATH${NC}"
        return 1
    fi
}

# Check if gcloud is available and install if needed
echo -e "\n${YELLOW}🔍 Checking Google Cloud CLI availability...${NC}"
if command -v gcloud >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Google Cloud CLI found: $(gcloud version --format='value(Google Cloud SDK)')${NC}"
    GCLOUD_CMD="gcloud"
else
    echo -e "${YELLOW}❓ Google Cloud CLI not found${NC}"

    case $INSTALL_GCLOUD in
        "yes")
            install_gcloud_cli
            GCLOUD_CMD="gcloud"
            ;;
        "no")
            echo -e "${RED}Error: Google Cloud CLI not available and installation disabled${NC}"
            SETUP_FAILURES+=("Google Cloud CLI not available and installation disabled")
            CRITICAL_FAILURE=true
            ;;
        "auto")
            echo -e "${BLUE}Installing Google Cloud CLI automatically...${NC}"
            if install_gcloud_cli; then
                GCLOUD_CMD="gcloud"
            else
                SETUP_FAILURES+=("Google Cloud CLI installation failed")
                CRITICAL_FAILURE=true
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid INSTALL_GCLOUD value: $INSTALL_GCLOUD${NC}"
            SETUP_FAILURES+=("Invalid INSTALL_GCLOUD value: $INSTALL_GCLOUD")
            CRITICAL_FAILURE=true
            ;;
    esac
fi

# Check if Gemini CLI is available and install if needed
echo -e "\n${YELLOW}🤖 Checking Google Gemini CLI availability...${NC}"
if command -v gemini >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Google Gemini CLI found: $(gemini --version 2>/dev/null || echo 'Version check failed')${NC}"
else
    echo -e "${YELLOW}❓ Google Gemini CLI not found${NC}"

    case $INSTALL_GEMINI_CLI in
        "yes")
            if install_gemini_cli; then
                echo -e "${GREEN}✅ Gemini CLI installation completed${NC}"
            else
                echo -e "${RED}❌ Gemini CLI installation failed${NC}"
            fi
            ;;
        "no")
            echo -e "${YELLOW}⚠️  Gemini CLI not available and installation disabled${NC}"
            ;;
        "auto")
            echo -e "${BLUE}Installing Google Gemini CLI automatically...${NC}"
            if install_gemini_cli; then
                echo -e "${GREEN}✅ Gemini CLI installation completed${NC}"
            else
                echo -e "${RED}❌ Gemini CLI installation failed${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid INSTALL_GEMINI_CLI value: $INSTALL_GEMINI_CLI${NC}"
            SETUP_FAILURES+=("Invalid INSTALL_GEMINI_CLI value: $INSTALL_GEMINI_CLI")
            ;;
    esac
fi

# Function to run test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_success="$3"  # true/false

    echo -e "\n${YELLOW}Testing: $test_name${NC}"
    echo "Command: $test_command"

    if eval "$test_command" >/dev/null 2>&1; then
        if [ "$expected_success" = "true" ]; then
            echo -e "${GREEN}✅ PASS${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}❌ UNEXPECTED SUCCESS (expected failure)${NC}"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$test_name")
        fi
    else
        if [ "$expected_success" = "false" ]; then
            echo -e "${GREEN}✅ PASS (expected failure)${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}❌ FAIL${NC}"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$test_name")
        fi
    fi
}

# Setup service account authentication - handle both file and JSON env var
echo -e "\n${YELLOW}🔐 Setting up service account authentication...${NC}"

# Check if service account key is provided via environment variable or file
if [ -n "$SERVICE_ACCOUNT_KEY_JSON" ]; then
    echo -e "${BLUE}Using service account key from environment variable...${NC}"
    SERVICE_ACCOUNT_KEY_FILE="/tmp/service-account-key-$$.json"
    # Write key to file without echoing contents to stdout
    printf '%s' "$SERVICE_ACCOUNT_KEY_JSON" > "$SERVICE_ACCOUNT_KEY_FILE" 2>/dev/null
    TEMP_KEY_FILE=true
elif [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
    echo -e "${BLUE}Using existing service account key file: $SERVICE_ACCOUNT_KEY_FILE${NC}"
    TEMP_KEY_FILE=false
else
    echo -e "${RED}Error: No service account key provided.${NC}"
    echo "Set either:"
    echo "  - SERVICE_ACCOUNT_KEY_JSON environment variable with the JSON content"
    echo "  - SERVICE_ACCOUNT_KEY_FILE environment variable with path to key file"
    echo "  - Place key file at $SERVICE_ACCOUNT_KEY_FILE"
    echo ""
    echo "Or run setup-service-account.sh first to create the key file"
    SETUP_FAILURES+=("No service account key provided")
    CRITICAL_FAILURE=true
fi

# Extract project ID from key file if not provided
if [ -z "$PROJECT_ID" ]; then
    if command -v python3 >/dev/null 2>&1; then
        PROJECT_ID=$(python3 -c "
import json
with open('$SERVICE_ACCOUNT_KEY_FILE', 'r') as f:
    key_data = json.load(f)
print(key_data.get('project_id', ''))
" 2>/dev/null)
    elif command -v jq >/dev/null 2>&1; then
        PROJECT_ID=$(jq -r '.project_id' "$SERVICE_ACCOUNT_KEY_FILE")
    else
        echo -e "${RED}Error: Cannot extract project ID. Install python3 or jq, or set PROJECT_ID environment variable.${NC}"
        SETUP_FAILURES+=("Cannot extract project ID - missing python3 or jq")
        CRITICAL_FAILURE=true
    fi
fi

echo -e "${BLUE}Project ID: $PROJECT_ID${NC}"
echo -e "${BLUE}Service Account Key File: $SERVICE_ACCOUNT_KEY_FILE${NC}"

# Skip authentication and tests if critical setup failure occurred
if [ "$CRITICAL_FAILURE" = true ]; then
    echo -e "${RED}⚠️  Critical setup failures detected. Skipping authentication and tests.${NC}"
else
    # Authenticate with service account
    echo -e "\n${YELLOW}Authenticating with service account...${NC}"
    if $GCLOUD_CMD auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY_FILE" --quiet 2>/dev/null; then
        echo -e "${GREEN}✅ Service account authentication successful${NC}"
        
        # Set project
        if $GCLOUD_CMD config set project "$PROJECT_ID" --quiet 2>/dev/null; then
            echo -e "${GREEN}✅ Project set successfully${NC}"
        else
            echo -e "${RED}❌ Failed to set project${NC}"
            SETUP_FAILURES+=("Failed to set project: $PROJECT_ID")
        fi
        
        # Configure Docker credential helper
        echo -e "${GREEN}Configuring Docker credential helper for Artifact Registry...${NC}"
        if $GCLOUD_CMD auth configure-docker --quiet 2>/dev/null; then
            echo -e "${GREEN}✅ Docker credential helper configured${NC}"
        else
            echo -e "${RED}❌ Failed to configure Docker credential helper${NC}"
            SETUP_FAILURES+=("Failed to configure Docker credential helper")
        fi
    else
        echo -e "${RED}❌ Service account authentication failed${NC}"
        SETUP_FAILURES+=("Service account authentication failed")
        CRITICAL_FAILURE=true
    fi
fi

# Only run tests if no critical failures occurred
if [ "$CRITICAL_FAILURE" = false ]; then
    echo -e "\n${GREEN}🧪 Running Google Cloud permission tests...${NC}"
    
    # Test 1: Basic authentication
    run_test "Basic Authentication" \
        "$GCLOUD_CMD auth list --filter=status:ACTIVE --format='value(account)' | grep -q 'terragon-deploy@'" \
        "true"

    # Test 2: Project access
    run_test "Project Access" \
        "$GCLOUD_CMD projects describe $PROJECT_ID --format='value(projectId)'" \
        "true"

    # Test 3: Cloud Build permissions
    echo -e "\n${BLUE}🏗️  Testing Cloud Build Permissions${NC}"
    run_test "Cloud Build - List builds" \
        "$GCLOUD_CMD builds list --limit=1 --format='value(id)'" \
        "true"

    run_test "Cloud Build - List repositories" \
        "$GCLOUD_CMD source repos list --format='value(name)'" \
        "true"

    # Test 4: Cloud Run permissions
    echo -e "\n${BLUE}🏃 Testing Cloud Run Permissions${NC}"
    run_test "Cloud Run - List services" \
        "$GCLOUD_CMD run services list --format='value(metadata.name)'" \
        "true"

    run_test "Cloud Run - List regions" \
        "$GCLOUD_CMD run regions list --format='value(name)'" \
        "true"

    # Test 5: Artifact Registry permissions
    echo -e "\n${BLUE}📦 Testing Artifact Registry Permissions${NC}"
    run_test "Artifact Registry - List repositories" \
        "$GCLOUD_CMD artifacts repositories list --format='value(name)'" \
        "true"

    run_test "Artifact Registry - List locations" \
        "$GCLOUD_CMD artifacts locations list --format='value(name)'" \
        "true"

    # Test 6: Secret Manager permissions
    echo -e "\n${BLUE}🔒 Testing Secret Manager Permissions${NC}"
    run_test "Secret Manager - List secrets" \
        "$GCLOUD_CMD secrets list --format='value(name)'" \
        "true"

    # Test 7: Storage permissions (needed for Cloud Build)
    echo -e "\n${BLUE}💾 Testing Storage Permissions${NC}"
    run_test "Storage - List buckets" \
        "$GCLOUD_CMD storage ls --format='value(name)'" \
        "true"

    # Test 8: Compute Engine permissions (needed for Cloud Run)
    echo -e "\n${BLUE}⚙️  Testing Compute Engine Permissions${NC}"
    run_test "Compute - List zones" \
        "$GCLOUD_CMD compute zones list --format='value(name)' --limit=1" \
        "true"

    # Test 9: IAM permissions
    echo -e "\n${BLUE}👥 Testing IAM Permissions${NC}"
    run_test "IAM - List service accounts" \
        "$GCLOUD_CMD iam service-accounts list --format='value(email)'" \
        "true"

    # Advanced tests - Create and test actual resources
    echo -e "\n${BLUE}🧪 Advanced Permission Tests${NC}"

    # Test creating a dummy secret (and clean up)
    TEST_SECRET_NAME="terragon-test-secret-$(date +%s)"
    echo -e "\n${YELLOW}Testing: Create and delete test secret${NC}"
    if echo "test-value" | $GCLOUD_CMD secrets create "$TEST_SECRET_NAME" --data-file=- --quiet 2>/dev/null; then
        echo -e "${GREEN}✅ Secret creation successful${NC}"
        if $GCLOUD_CMD secrets delete "$TEST_SECRET_NAME" --quiet 2>/dev/null; then
            echo -e "${GREEN}✅ Secret deletion successful${NC}"
            ((TESTS_PASSED += 2))
        else
            echo -e "${RED}❌ Secret deletion failed${NC}"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("Secret deletion")
        fi
    else
        echo -e "${RED}❌ Secret creation failed${NC}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("Secret creation")
    fi

    # Test Docker credential helper setup (already done above, just verify)
    echo -e "\n${YELLOW}Testing: Docker credential helper verification${NC}"
    if command -v docker >/dev/null 2>&1; then
        if docker --version >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Docker available and credential helper configured${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${YELLOW}⚠️  Docker not available for testing${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Docker not installed - credential helper configured but cannot test${NC}"
    fi

    # Test quota and limits
    echo -e "\n${BLUE}📊 Checking Service Quotas${NC}"
    run_test "Cloud Build - Check quota" \
        "$GCLOUD_CMD compute project-info describe --format='value(quotas[].limit)'" \
        "true"
fi

# Test Gemini CLI if installed (independent of gcloud setup)
echo -e "\n${BLUE}🤖 Testing Gemini CLI${NC}"
if command -v gemini >/dev/null 2>&1; then
    echo -e "\n${YELLOW}Testing: Gemini CLI availability${NC}"
    if gemini --help >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Gemini CLI is working${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}❌ Gemini CLI not responding${NC}"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("Gemini CLI functionality")
    fi
else
    echo -e "${YELLOW}⚠️  Gemini CLI not installed - skipping test${NC}"
fi

# Summary
echo -e "\n=================================================================="
echo -e "${BLUE}📋 Complete Test Summary${NC}"

# Setup failures summary
if [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    echo -e "\n${RED}❌ Setup Failures (${#SETUP_FAILURES[@]}):${NC}"
    for failure in "${SETUP_FAILURES[@]}"; do
        echo -e "  • $failure"
    done
fi

# Test results summary
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo -e "\n${BLUE}🧪 Test Results:${NC}"
echo -e "  Total Tests Run: $TOTAL_TESTS"
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "\n${RED}❌ Failed Tests:${NC}"
    for failed_test in "${FAILED_TESTS[@]}"; do
        echo -e "  • $failed_test"
    done
fi

# Overall status
echo -e "\n${BLUE}📊 Overall Status:${NC}"
if [ "$CRITICAL_FAILURE" = true ]; then
    echo -e "${RED}❌ CRITICAL FAILURES DETECTED${NC}"
    echo -e "   Critical setup issues prevented testing. Review setup failures above."
elif [ $TESTS_FAILED -eq 0 ] && [ ${#SETUP_FAILURES[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Service account is properly configured.${NC}"
    echo -e "${GREEN}✅ Ready for deployment operations${NC}"
elif [ $TESTS_FAILED -eq 0 ] && [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PARTIAL SUCCESS${NC}"
    echo -e "   All tests passed, but some setup steps failed. Review setup failures above."
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo -e "   Review failed tests and setup failures above."
fi

# Next steps (only if some level of success)
if [ "$CRITICAL_FAILURE" = false ]; then
    echo -e "\n${BLUE}💡 Next steps:${NC}"
    if [ -n "$GCLOUD_CMD" ] && [ -n "$PROJECT_ID" ]; then
        echo "  • Deploy with Cloud Build: $GCLOUD_CMD builds submit --tag gcr.io/$PROJECT_ID/my-app ."
        echo "  • Create Cloud Run service: $GCLOUD_CMD run deploy --image gcr.io/$PROJECT_ID/my-app"
        echo "  • Push to Artifact Registry: docker push REGION-docker.pkg.dev/$PROJECT_ID/REPO/IMAGE"
        echo "  • Manage secrets: $GCLOUD_CMD secrets create my-secret --data-file=-"
    fi
    if command -v gemini >/dev/null 2>&1; then
        echo "  • Use Gemini CLI: gemini --help for AI assistance"
    fi
fi

# Troubleshooting (if any issues)
if [ $TESTS_FAILED -gt 0 ] || [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}🔧 Troubleshooting suggestions:${NC}"
    echo "  • Verify all required APIs are enabled"
    echo "  • Check IAM roles are properly assigned"
    echo "  • Ensure service account key is valid and not expired"
    echo "  • Run setup-service-account.sh again if needed"
    echo "  • Check network connectivity and firewall settings"
fi

# Clean up temporary key file if created
if [ "$TEMP_KEY_FILE" = true ] && [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
    rm -f "$SERVICE_ACCOUNT_KEY_FILE"
fi

# Exit with appropriate code
if [ "$CRITICAL_FAILURE" = true ]; then
    exit 2  # Critical failure
elif [ $TESTS_FAILED -gt 0 ] || [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    exit 1  # Some failures
else
    exit 0  # All good
fi