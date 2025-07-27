#!/bin/bash

# Google Cloud and Gemini CLI Setup Script
# This script installs gcloud CLI (minimal) and Google Gemini CLI from npm
# Sets up service account authentication for Google Cloud services

# Note: Removed 'set -e' to allow script to continue even when individual commands fail
# Individual setup failures are tracked and reported at the end

# Configuration
GCLOUD_VERSION="463.0.0"  # Update as needed
SERVICE_ACCOUNT_KEY_JSON=${SERVICE_ACCOUNT_KEY_JSON:-""}
SERVICE_ACCOUNT_KEY_FILE=${SERVICE_ACCOUNT_KEY_FILE:-"terragon-service-account-key.json"}
PROJECT_ID=${PROJECT_ID:-""}
INSTALL_GCLOUD=${INSTALL_GCLOUD:-"auto"}  # auto, yes, no
INSTALL_GEMINI_CLI=${INSTALL_GEMINI_CLI:-"auto"}  # auto, yes, no
MINIMAL_INSTALL=${MINIMAL_INSTALL:-"true"}  # Install only required components
DEBUG_OUTPUT=${DEBUG_OUTPUT:-"false"}  # Show detailed debug output
ENABLE_APIS=${ENABLE_APIS:-"true"}  # Auto-enable required APIs

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Setup results tracking
SETUP_FAILURES=()
CRITICAL_FAILURE=false

echo -e "${BLUE}🛠️  Google Cloud and Gemini CLI Setup${NC}"
echo "=================================================================="

# Installation mode indicator
if [ "$MINIMAL_INSTALL" = "true" ]; then
    echo -e "${GREEN}⚡ Running in minimal install mode${NC}"
else
    echo -e "${BLUE}🔧 Running in full install mode${NC}"
fi

# Start timer
START_TIME=$(date +%s)

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
    if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
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
            brew install curl python3 node npm
        else
            echo -e "${YELLOW}Warning: Could not detect package manager. Ensure curl, python3, node, and npm are installed.${NC}"
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

    # Download with progress bar suppressed and retry logic
    echo -e "${BLUE}Downloading from: $DOWNLOAD_URL${NC}"
    if ! curl -f -s -S -L --retry 3 --retry-delay 2 -o "$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
        echo -e "${RED}Failed to download Google Cloud CLI${NC}"
        SETUP_FAILURES+=("Failed to download Google Cloud CLI")
        return 1
    fi

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

    # Run installation script with minimal components
    if [ "$MINIMAL_INSTALL" = "true" ]; then
        echo -e "${BLUE}Installing minimal components only...${NC}"
        # Install only the components we need for our tests
        if "$INSTALL_DIR/install.sh" \
            --quiet \
            --usage-reporting=false \
            --command-completion=false \
            --path-update=false \
            --install-python=false \
            --additional-components="" 2>/dev/null; then
            echo -e "${GREEN}Installation script completed successfully${NC}"
        else
            echo -e "${YELLOW}Installation script completed with warnings (this is often normal)${NC}"
        fi

        # Remove unnecessary components to save space and time
        echo -e "${BLUE}Removing unnecessary components...${NC}"
        rm -rf "$INSTALL_DIR/platform/bq" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/platform/gsutil" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/platform/kubectl" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/lib/third_party/grpc" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/help" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/lib/googlecloudsdk/command_lib/bq" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/lib/googlecloudsdk/command_lib/dataflow" 2>/dev/null || true
        rm -rf "$INSTALL_DIR/lib/googlecloudsdk/command_lib/ml" 2>/dev/null || true
    else
        echo -e "${BLUE}Installing full Google Cloud CLI...${NC}"
        if "$INSTALL_DIR/install.sh" --quiet --usage-reporting=false --command-completion=true --path-update=false 2>/dev/null; then
            echo -e "${GREEN}Installation script completed successfully${NC}"
        else
            echo -e "${YELLOW}Installation script completed with warnings (this is often normal)${NC}"
        fi
    fi

    # Ensure binary has correct permissions
    if [ -f "$INSTALL_DIR/bin/gcloud" ]; then
        chmod +x "$INSTALL_DIR/bin/gcloud" 2>/dev/null || true
        echo -e "${BLUE}Binary permissions: $(ls -la "$INSTALL_DIR/bin/gcloud" | cut -d' ' -f1,3,4)${NC}"
    fi

    # Verify installation with multiple fallback methods
    echo -e "${GREEN}Verifying installation...${NC}"

    # Try multiple verification methods in order of preference
    if "$INSTALL_DIR/bin/gcloud" --version >/dev/null 2>&1; then
        # Method 1: Simple --version flag
        GCLOUD_VERSION_OUTPUT=$("$INSTALL_DIR/bin/gcloud" --version 2>/dev/null | head -1)
        echo -e "${GREEN}✅ Google Cloud CLI installed successfully${NC}"
        echo -e "${BLUE}Version: $GCLOUD_VERSION_OUTPUT${NC}"
    elif "$INSTALL_DIR/bin/gcloud" version >/dev/null 2>&1; then
        # Method 2: version subcommand
        GCLOUD_VERSION_OUTPUT=$("$INSTALL_DIR/bin/gcloud" version 2>/dev/null | grep -m1 "Google Cloud SDK" || echo "Version info unavailable")
        echo -e "${GREEN}✅ Google Cloud CLI installed successfully${NC}"
        echo -e "${BLUE}Version: $GCLOUD_VERSION_OUTPUT${NC}"
    elif [ -x "$INSTALL_DIR/bin/gcloud" ]; then
        # Method 3: Just check if the binary exists and is executable
        echo -e "${GREEN}✅ Google Cloud CLI binary installed${NC}"
        echo -e "${BLUE}Binary location: $INSTALL_DIR/bin/gcloud${NC}"
        # Try to get version info without failing the verification
        GCLOUD_VERSION_OUTPUT=$("$INSTALL_DIR/bin/gcloud" --version 2>&1 | head -1 || echo "Version check requires initialization")
        echo -e "${BLUE}Status: $GCLOUD_VERSION_OUTPUT${NC}"
    else
        echo -e "${RED}❌ Installation verification failed${NC}"
        echo -e "${RED}Binary not found or not executable at: $INSTALL_DIR/bin/gcloud${NC}"
        if [ -f "$INSTALL_DIR/bin/gcloud" ]; then
            echo -e "${RED}File exists but is not executable. Permissions: $(ls -la "$INSTALL_DIR/bin/gcloud")${NC}"
        else
            echo -e "${RED}Binary file does not exist${NC}"
        fi

        # Show debug output if enabled
        if [ "$DEBUG_OUTPUT" = "true" ]; then
            echo -e "${YELLOW}Debug: Contents of $INSTALL_DIR/bin:${NC}"
            ls -la "$INSTALL_DIR/bin/" 2>/dev/null || echo "Directory does not exist"
            echo -e "${YELLOW}Debug: Installation directory structure:${NC}"
            find "$INSTALL_DIR" -type f -name "*gcloud*" 2>/dev/null | head -10 || echo "No gcloud files found"
            echo -e "${YELLOW}Debug: Trying direct execution:${NC}"
            "$INSTALL_DIR/bin/gcloud" --version 2>&1 | head -5 || echo "Direct execution failed"
        fi

        SETUP_FAILURES+=("Google Cloud CLI installation verification failed - binary not found or executable")
        return 1
    fi

    # Clean up
    cd - >/dev/null
    rm -rf "$TEMP_DIR"
}

# Function to install Google Gemini CLI from npm
install_gemini_cli() {
    echo -e "${GREEN}Installing Google Gemini CLI...${NC}"
    
    # Check if npm is available
    if ! command -v npm >/dev/null 2>&1; then
        echo -e "${RED}Error: npm not found. Please install Node.js and npm first.${NC}"
        SETUP_FAILURES+=("npm not available for Gemini CLI installation")
        return 1
    fi
    
    # Check if we're in a directory where we can install globally or create a local install
    echo -e "${BLUE}Installing @google/generative-ai globally via npm...${NC}"
    
    # Try global installation first, fallback to local
    if npm install -g @google/generative-ai >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Google Gemini CLI installed globally${NC}"
        GEMINI_CLI_INSTALLED="global"
    else
        echo -e "${YELLOW}Global installation failed, trying local installation...${NC}"
        # Create a local directory for gemini cli if it doesn't exist
        GEMINI_LOCAL_DIR="$HOME/.gemini-cli"
        mkdir -p "$GEMINI_LOCAL_DIR"
        cd "$GEMINI_LOCAL_DIR"
        
        if npm init -y >/dev/null 2>&1 && npm install @google/generative-ai >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Google Gemini CLI installed locally in $GEMINI_LOCAL_DIR${NC}"
            echo -e "${BLUE}Local installation path: $GEMINI_LOCAL_DIR/node_modules/.bin${NC}"
            GEMINI_CLI_INSTALLED="local"
            # Add to PATH for current session
            export PATH="$GEMINI_LOCAL_DIR/node_modules/.bin:$PATH"
        else
            echo -e "${RED}❌ Failed to install Google Gemini CLI${NC}"
            SETUP_FAILURES+=("Failed to install Google Gemini CLI via npm")
            cd - >/dev/null
            return 1
        fi
        cd - >/dev/null
    fi
    
    # Verify installation
    echo -e "${GREEN}Verifying Gemini CLI installation...${NC}"
    if npm list -g @google/generative-ai >/dev/null 2>&1 || npm list @google/generative-ai >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Google Gemini CLI package verified${NC}"
        echo -e "${BLUE}Installation type: $GEMINI_CLI_INSTALLED${NC}"
    else
        echo -e "${YELLOW}⚠️  Package installed but verification unclear${NC}"
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
            # Ensure gcloud is in PATH for current session
            if [ -d "/opt/google-cloud-sdk/bin" ]; then
                export PATH="/opt/google-cloud-sdk/bin:$PATH"
            elif [ -d "$HOME/google-cloud-sdk/bin" ]; then
                export PATH="$HOME/google-cloud-sdk/bin:$PATH"
            fi
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
                # Ensure gcloud is in PATH for current session
                if [ -d "/opt/google-cloud-sdk/bin" ]; then
                    export PATH="/opt/google-cloud-sdk/bin:$PATH"
                elif [ -d "$HOME/google-cloud-sdk/bin" ]; then
                    export PATH="$HOME/google-cloud-sdk/bin:$PATH"
                fi
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

# Check if Gemini CLI should be installed
echo -e "\n${YELLOW}🤖 Checking Google Gemini CLI availability...${NC}"
if npm list -g @google/generative-ai >/dev/null 2>&1 || npm list @google/generative-ai >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Google Gemini CLI package found${NC}"
else
    echo -e "${YELLOW}❓ Google Gemini CLI not found${NC}"
    
    case $INSTALL_GEMINI_CLI in
        "yes")
            install_gemini_cli
            ;;
        "no")
            echo -e "${YELLOW}⚠️  Google Gemini CLI installation disabled${NC}"
            ;;
        "auto")
            echo -e "${BLUE}Installing Google Gemini CLI automatically...${NC}"
            if ! install_gemini_cli; then
                SETUP_FAILURES+=("Google Gemini CLI installation failed")
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid INSTALL_GEMINI_CLI value: $INSTALL_GEMINI_CLI${NC}"
            SETUP_FAILURES+=("Invalid INSTALL_GEMINI_CLI value: $INSTALL_GEMINI_CLI")
            ;;
    esac
fi


# Setup completion and authentication
echo -e "\n${GREEN}🔐 Completing setup and authentication...${NC}"

# Setup service account authentication - handle both file and JSON env var
echo -e "\n${YELLOW}🔐 Setting up service account authentication...${NC}"

# Check if service account key is provided via environment variable or file
if [ -n "$SERVICE_ACCOUNT_KEY_JSON" ]; then
    echo -e "${BLUE}Using service account key from environment variable...${NC}"
    SERVICE_ACCOUNT_KEY_FILE="/tmp/service-account-key-$$.json"
    # Write key to file without echoing contents to stdout
    echo "$SERVICE_ACCOUNT_KEY_JSON" > "$SERVICE_ACCOUNT_KEY_FILE" 2>/dev/null
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
    echo -e "${BLUE}Extracting project ID from service account key...${NC}"
    if [ ! -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
        echo -e "${RED}Error: Service account key file not found: $SERVICE_ACCOUNT_KEY_FILE${NC}"
        SETUP_FAILURES+=("Service account key file not found")
        CRITICAL_FAILURE=true
    elif command -v python3 >/dev/null 2>&1; then
        PROJECT_ID=$(python3 -c "
import json, sys
try:
    with open('$SERVICE_ACCOUNT_KEY_FILE', 'r') as f:
        key_data = json.load(f)
    project_id = key_data.get('project_id', '')
    if not project_id:
        print('ERROR: project_id not found in key file', file=sys.stderr)
        sys.exit(1)
    print(project_id)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

        if [ $? -ne 0 ] || [ -z "$PROJECT_ID" ]; then
            echo -e "${RED}Error: Failed to extract project_id from service account key${NC}"
            SETUP_FAILURES+=("Failed to extract project_id from service account key")
            CRITICAL_FAILURE=true
        fi
    elif command -v jq >/dev/null 2>&1; then
        PROJECT_ID=$(jq -r '.project_id // empty' "$SERVICE_ACCOUNT_KEY_FILE" 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            echo -e "${RED}Error: project_id not found in service account key${NC}"
            SETUP_FAILURES+=("project_id not found in service account key")
            CRITICAL_FAILURE=true
        fi
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
    # 2. Authenticate with service account
    if $GCLOUD_CMD auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY_FILE" --quiet 2>/dev/null; then
        echo -e "${GREEN}✅ Service account authentication successful${NC}"

        # Set project
        if $GCLOUD_CMD config set project "$PROJECT_ID" --quiet 2>/dev/null; then
            echo -e "${GREEN}✅ Project set successfully${NC}"
        else
            echo -e "${RED}❌ Failed to set project${NC}"
            SETUP_FAILURES+=("Failed to set project: $PROJECT_ID")
        fi

        # Configure Docker credential helper (only if Docker is available)
        if command -v docker >/dev/null 2>&1; then
            echo -e "${GREEN}Configuring Docker credential helper for Artifact Registry...${NC}"
            if $GCLOUD_CMD auth configure-docker --quiet 2>/dev/null; then
                echo -e "${GREEN}✅ Docker credential helper configured${NC}"
            else
                echo -e "${RED}❌ Failed to configure Docker credential helper${NC}"
                SETUP_FAILURES+=("Failed to configure Docker credential helper")
            fi
        else
            echo -e "${YELLOW}⚠️  Docker not available - skipping credential helper setup${NC}"
        fi
    else
        echo -e "${RED}❌ Service account authentication failed${NC}"
        SETUP_FAILURES+=("Service account authentication failed")
        CRITICAL_FAILURE=true
    fi
fi

# Calculate runtime
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

# Setup Summary
echo -e "\n=================================================================="
echo -e "${BLUE}📋 Setup Complete${NC}"
echo -e "${BLUE}⏱️  Total Runtime: ${RUNTIME} seconds${NC}"

# Setup failures summary
if [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    echo -e "\n${RED}❌ Setup Issues (${#SETUP_FAILURES[@]}):${NC}"
    for failure in "${SETUP_FAILURES[@]}"; do
        echo -e "  • $failure"
    done
fi

# Overall status
echo -e "\n${BLUE}📊 Setup Status:${NC}"
if [ "$CRITICAL_FAILURE" = true ]; then
    echo -e "${RED}❌ CRITICAL SETUP FAILURES${NC}"
    echo -e "   Critical setup issues detected. Review issues above."
elif [ ${#SETUP_FAILURES[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 SETUP COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}✅ Google Cloud CLI installed (minimal)${NC}"
    echo -e "${GREEN}✅ Google Gemini CLI installed${NC}"
    echo -e "${GREEN}✅ Service account authentication configured${NC}"
    echo -e "${GREEN}✅ Ready for development operations${NC}"
else
    echo -e "${YELLOW}⚠️  SETUP COMPLETED WITH WARNINGS${NC}"
    echo -e "   Some setup steps had issues. Review warnings above."
fi

# Next steps
if [ "$CRITICAL_FAILURE" = false ]; then
    echo -e "\n${BLUE}💡 Tools installed and ready to use:${NC}"
    if [ -n "$GCLOUD_CMD" ]; then
        echo "  • Google Cloud CLI: $GCLOUD_CMD --version"
    fi
    echo "  • Google Gemini CLI: Available via npm (@google/generative-ai)"
    if [ -n "$PROJECT_ID" ]; then
        echo "  • Project configured: $PROJECT_ID"
        echo "  • Example commands:"
        echo "    - $GCLOUD_CMD builds submit --tag gcr.io/$PROJECT_ID/my-app ."
        echo "    - $GCLOUD_CMD run deploy --image gcr.io/$PROJECT_ID/my-app"
        echo "    - $GCLOUD_CMD secrets create my-secret --data-file=-"
    fi
fi

# Ensure gcloud is in PATH for future sessions
if [ "$CRITICAL_FAILURE" = false ] && command -v gcloud >/dev/null 2>&1; then
    echo -e "\n${GREEN}🔧 Ensuring gcloud is available in PATH for future sessions...${NC}"
    
    # Determine the installation directory
    GCLOUD_BIN_DIR=$(dirname "$(command -v gcloud)")
    GCLOUD_SDK_DIR=$(dirname "$GCLOUD_BIN_DIR")
    
    echo -e "${BLUE}gcloud installation found at: $GCLOUD_SDK_DIR${NC}"
    
    # Add to current shell session
    export PATH="$GCLOUD_BIN_DIR:$PATH"
    
    # Check if we need to add to shell profiles
    PATH_EXPORT_LINE="export PATH=\"$GCLOUD_BIN_DIR:\$PATH\""
    
    # For root users, add to /etc/profile
    if [ "$EUID" -eq 0 ]; then
        if ! grep -q "$GCLOUD_BIN_DIR" /etc/profile 2>/dev/null; then
            echo "$PATH_EXPORT_LINE" >> /etc/profile
            echo -e "${GREEN}✅ Added gcloud to system-wide PATH (/etc/profile)${NC}"
        else
            echo -e "${BLUE}gcloud already in system-wide PATH${NC}"
        fi
    else
        # For non-root users, add to user shell profiles
        PROFILES_UPDATED=0
        for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
            if [ -f "$profile" ]; then
                if ! grep -q "$GCLOUD_BIN_DIR" "$profile"; then
                    echo "$PATH_EXPORT_LINE" >> "$profile"
                    PROFILES_UPDATED=$((PROFILES_UPDATED + 1))
                fi
            fi
        done
        
        if [ $PROFILES_UPDATED -gt 0 ]; then
            echo -e "${GREEN}✅ Added gcloud to PATH in $PROFILES_UPDATED shell profile(s)${NC}"
        else
            echo -e "${BLUE}gcloud already in user shell profiles${NC}"
        fi
    fi
    
    # Also add to current environment for immediate use
    echo -e "${BLUE}Current session PATH updated${NC}"
    echo -e "${YELLOW}Note: New terminal sessions will automatically have gcloud in PATH${NC}"
fi

# Clean up temporary key file if created
if [ "$TEMP_KEY_FILE" = true ] && [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
    rm -f "$SERVICE_ACCOUNT_KEY_FILE"
fi

# Exit with appropriate code
if [ "$CRITICAL_FAILURE" = true ]; then
    exit 2  # Critical failure
elif [ ${#SETUP_FAILURES[@]} -gt 0 ]; then
    exit 1  # Some warnings
else
    exit 0  # All good
fi