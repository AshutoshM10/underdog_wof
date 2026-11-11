#!/usr/bin/env bash
# ==============================================================================
# Underdog Woof - macOS Setup Script
# ==============================================================================
set -e

# Change to the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

VENV_DIR="$SCRIPT_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
MODEL_WEIGHTS="$SCRIPT_DIR/woof_int8.npz"

# ==============================================================================
# Pre-Flight Check
# ==============================================================================
echo -e "${BOLD}${BLUE}==> Underdog Woof: Pre-Flight Check${NC}"

PREFLIGHT_READY=1
MISSING_REASONS=()

if [ ! -x "$VENV_PYTHON" ]; then
    PREFLIGHT_READY=0
    MISSING_REASONS+=("Virtual environment (.venv) is not installed")
else
    if ! "$VENV_PYTHON" -c "import numpy" 2>/dev/null; then
        PREFLIGHT_READY=0
        MISSING_REASONS+=("NumPy is missing in .venv")
    fi
    if ! "$VENV_PYTHON" -c "import underdog_woof" 2>/dev/null; then
        PREFLIGHT_READY=0
        MISSING_REASONS+=("underdog_woof package cannot be imported")
    fi
fi

if [ ! -f "$MODEL_WEIGHTS" ]; then
    PREFLIGHT_READY=0
    MISSING_REASONS+=("Model weights file (woof_int8.npz) is missing")
fi

# If pre-flight passes and no force flag is provided, skip setup
if [ "$PREFLIGHT_READY" -eq 1 ] && [ "$1" != "--force" ] && [ "$1" != "-f" ]; then
    NUMPY_VER=$("$VENV_PYTHON" -c "import numpy; print(numpy.__version__)")
    PYTHON_VER=$("$VENV_PYTHON" --version)
    echo -e "${GREEN}✓ Pre-flight check PASSED! All requirements are already met:${NC}"
    echo -e "  - Environment:  ${BOLD}.venv${NC} ($PYTHON_VER)"
    echo -e "  - NumPy:        ${BOLD}v${NUMPY_VER}${NC}"
    echo -e "  - Model:        ${BOLD}woof_int8.npz${NC} found"
    echo -e "\n${BOLD}Ready to run:${NC}"
    echo -e "  ./woof \"Call 020 7946 0018 before 6:15.\" -o hello.wav"
    echo -e "  ./woof --web   ${BLUE}# Launch browser UI at http://127.0.0.1:8000${NC}"
    echo -e "\n${YELLOW}(Pass --force to re-run setup if you wish to rebuild the environment)${NC}"
    exit 0
fi

# ==============================================================================
# Full Setup (Executed only when pre-flight fails or --force is supplied)
# ==============================================================================
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}Force flag detected. Proceeding with full setup...${NC}\n"
else
    echo -e "${YELLOW}Pre-flight check found missing components:${NC}"
    for reason in "${MISSING_REASONS[@]}"; do
        echo -e "  ${RED}✗${NC} $reason"
    done
    echo -e "\n${BLUE}Proceeding with setup...${NC}\n"
fi

# 1. Detect best available Python 3 on macOS
PYTHON_BIN=""
for candidate in \
    "/Library/Frameworks/Python.framework/Versions/3.15/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3" \
    "$(which python3.15 2>/dev/null)" \
    "$(which python3.14 2>/dev/null)" \
    "$(which python3.13 2>/dev/null)" \
    "/opt/homebrew/bin/python3" \
    "$(which python3 2>/dev/null)"
do
    if [ -x "$candidate" ]; then
        PYTHON_BIN="$candidate"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}Error: Python 3 was not found on your system.${NC}"
    echo "Please install Python using Homebrew: brew install python"
    exit 1
fi

echo -e "Using host Python: ${BOLD}$PYTHON_BIN${NC} ($($PYTHON_BIN --version))"

# 2. Check for model weights
if [ ! -f "$MODEL_WEIGHTS" ]; then
    echo -e "${YELLOW}Warning: woof_int8.npz not found.${NC}"
    echo "You can download it using:"
    echo "  hf download ConwayResearch/Underdog-Woof --local-dir ."
fi

# 3. Create Virtual Environment
if [ ! -d "$VENV_DIR" ] || [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    echo -e "${BLUE}Configuring virtual environment in .venv...${NC}"
    "$PYTHON_BIN" -m venv --system-site-packages "$VENV_DIR"
fi

# 4. Install dependencies inside the virtual environment
echo -e "${BLUE}Installing/verifying dependencies in .venv...${NC}"
"$VENV_PYTHON" -m pip install -q -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null || {
    # If offline, check if numpy is accessible via system site-packages
    if ! "$VENV_PYTHON" -c "import numpy" 2>/dev/null; then
        echo -e "${YELLOW}Attempting pip install numpy...${NC}"
        "$VENV_PYTHON" -m pip install -r "$SCRIPT_DIR/requirements.txt"
    fi
}

# 5. Verify installation
if "$VENV_PYTHON" -c "import numpy; import underdog_woof" 2>/dev/null; then
    NUMPY_VER=$("$VENV_PYTHON" -c "import numpy; print(numpy.__version__)")
    echo -e "${GREEN}✓ Verified underdog_woof and NumPy (${NUMPY_VER})${NC}"
else
    echo -e "${RED}Error: Failed to verify dependencies in the virtual environment.${NC}"
    exit 1
fi

# 6. Ensure the launcher script ./woof is executable
if [ -f "$SCRIPT_DIR/woof" ]; then
    chmod +x "$SCRIPT_DIR/woof"
fi

echo -e "\n${BOLD}${GREEN}==> Setup completed successfully!${NC}\n"
echo -e "You can now run Underdog Woof in two easy ways:"
echo -e "  ${BOLD}1. Using the ./woof shortcut:${NC}"
echo -e "     ./woof \"Hello! Call me back before 6:15.\" -o hello.wav"
echo -e "     ./woof --voice mira \"Hello from Mira.\" -o mira.wav"
echo -e "     ./woof --web   ${BLUE}# Launches browser Web UI at http://127.0.0.1:8000${NC}\n"
echo -e "  ${BOLD}2. Or activate the virtual environment manually:${NC}"
echo -e "     source .venv/bin/activate"
echo -e "     python -m underdog_woof \"Call 020 7946 0018 before 6:15.\" -o hello.wav"
echo -e "     python webui.py\n"
