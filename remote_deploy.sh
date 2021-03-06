#!/bin/bash

## title:         remote_deploy.sh
## description:   A dev script for deploying & compiling the `ZeroMQ Server` script and its dependencies from a
##                local dev environment into a remote MetaTrader 4 instance via SSH.
## precondition:  Deployment target is a Windows 10 instance which has MT4 (32-bit) installed, and
##                WSL (Windows Subsystem for Linux) installed which is running a SSH server. The client machine running
##                this script should have SSH master connections enabled to prevent excessive handshakes.
## postcondition: MetaTrader 4 will have the latest server script and should be restarted to apply it
##                (see restart_mt4.bat).
##
## configurable variables:
## ----------------------------------------------------------------------------

# the server script filename
SCRIPT_FILENAME='ZeroMQ_Server.mq4'

# the SSH endpoint of the deployment target
SSH_ENDPOINT='joe@win10'

# the remote MT4 profile location
MT4_PROFILE='C:\Users\Joe\AppData\Roaming\MetaQuotes\Terminal\B4465D2178C9DCD8E8CD3CCFEA8AA766'

# the remote MT4 install location
MT4_HOME='C:\Program Files (x86)\LMFX MetaTrader 4 Terminal'

## ----------------------------------------------------------------------------

# closes master connection and exits with code
function closeAndExit() {
  ssh -O exit "$SSH_ENDPOINT" &> /dev/null
  exit $1
}

echo "Deploying \"$SCRIPT_FILENAME\"..."

# start master connection
ssh -Nf "$SSH_ENDPOINT"

# Windows paths used by WSL must be converted into Linux format
WSL_MT4_PROFILE="$(ssh "$SSH_ENDPOINT" "echo \$(wslpath '$MT4_PROFILE')")"
WSL_MT4_HOME="$(ssh "$SSH_ENDPOINT" "echo \$(wslpath '$MT4_HOME')")"
SCRIPT_DIR="$(dirname "$(realpath -s "$0")")"
WIN_COMPILER_LOG="$MT4_PROFILE\\logs\\compiler.log"
WSL_COMPILER_LOG="$(ssh "$SSH_ENDPOINT" "echo \$(wslpath '$WIN_COMPILER_LOG')")"

if ssh "$SSH_ENDPOINT" "[ ! -d \"$WSL_MT4_PROFILE\" ]"; then
  echo "[ERROR] MetaTrader profile not found.  Deployment aborted."
  closeAndExit 1
fi

rsync -avh "$SCRIPT_DIR/mql-zmq/Include/" "$SSH_ENDPOINT:\"$WSL_MT4_PROFILE/MQL4/Include/\""
rsync -avh "$SCRIPT_DIR/mql-zmq/Library/MT4/" "$SSH_ENDPOINT:\"$WSL_MT4_PROFILE/MQL4/Libraries/\""
rsync -avh --exclude "MQL4/Include/json/README.md" --exclude "config/zeromq_server_startup.template.ini" "$SCRIPT_DIR/metatrader4/" "$SSH_ENDPOINT:\"$WSL_MT4_PROFILE/\""

# compile the server script
if ssh "$SSH_ENDPOINT" "[ ! -f \"$WSL_MT4_HOME/metaeditor.exe\" ]"; then
  echo "[WARNING] The MQL4 compiler was not found.  Skipping compilation..."
  closeAndExit 1
fi

echo -e "\nCompiling..."
if ssh "$SSH_ENDPOINT" "
  rm \"$WSL_COMPILER_LOG\" &> /dev/null
  cd \"$WSL_MT4_HOME\"
  ./metaeditor.exe /log:\"$WIN_COMPILER_LOG\" /compile:\"$MT4_PROFILE\\MQL4\\Scripts\\$SCRIPT_FILENAME\"
  [ ! -f \"$WSL_COMPILER_LOG\" ]"; then
  echo "[ERROR] Compiler log not found."
  closeAndExit 1
fi

# convert log to UTF-8 and direct any warnings/errors to local STDOUT
ssh "$SSH_ENDPOINT" "iconv -f utf-16 -t utf-8 \"$WSL_COMPILER_LOG\"" | grep -E --color=auto "warning|error"
closeAndExit 0
