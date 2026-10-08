#!/bin/bash
set -e -u -o pipefail

# Change to the directory where this script is located
cd "$(realpath "$(dirname "$0")")"

TERMUX_GENERATOR_HOME="$(pwd)"
TERMUX_APP__PACKAGE_NAME="com.termux"
TERMUX_APP_TYPE="f-droid"
DO_NOT_CLEAN=""
TERMUX_GENERATOR_PLUGIN=""
ADDITIONAL_PACKAGES="xkeyboard-config"
BOOTSTRAP_ARCHITECTURES=""
DISABLE_BOOTSTRAP_SECOND_STAGE=""
ENABLE_SSH_SERVER=""
DEFAULT_PASSWORD="changeme"
DISABLE_BOOTSTRAP=""
DISABLE_TERMINAL=""
DISABLE_TASKER=""
DISABLE_FLOAT=""
DISABLE_WIDGET=""
DISABLE_API=""
DISABLE_BOOT=""
DISABLE_STYLING=""
DISABLE_GUI=""
DISABLE_X11=""

source "$TERMUX_GENERATOR_HOME/scripts/termux_generator_utils.sh"
source "$TERMUX_GENERATOR_HOME/scripts/termux_generator_steps.sh"
source "$TERMUX_GENERATOR_HOME/scripts/termux_generator_all.sh"

show_usage() {
    echo "Usage: $0 [--name <pkg>] [--type f-droid|play-store] ..."
}

while (($# > 0)); do
    case "$1" in
        -d|--dirty) DO_NOT_CLEAN=1 ;;
        -h|--help) show_usage; exit 0 ;;
        -a|--add)
            ADDITIONAL_PACKAGES+=",$2"; shift 1 ;;
        -n|--name) TERMUX_APP__PACKAGE_NAME="$2"; shift 1 ;;
        -t|--type) TERMUX_APP_TYPE="$2"; shift 1 ;;
        --architectures) BOOTSTRAP_ARCHITECTURES="$2"; shift 1 ;;
        -p|--plugin) TERMUX_GENERATOR_PLUGIN="$2"; shift 1 ;;
        --disable-bootstrap-second-stage) DISABLE_BOOTSTRAP_SECOND_STAGE=1 ;;
        --enable-ssh-server) ENABLE_SSH_SERVER=1 ;;
        --disable-bootstrap) DISABLE_BOOTSTRAP=1 ;;
        --disable-terminal) DISABLE_TERMINAL=1 ;;
        --disable-tasker) DISABLE_TASKER=1 ;;
        --disable-float) DISABLE_FLOAT=1 ;;
        --disable-widget) DISABLE_WIDGET=1 ;;
        --disable-api) DISABLE_API=1 ;;
        --disable-boot) DISABLE_BOOT=1 ;;
        --disable-styling) DISABLE_STYLING=1 ;;
        --disable-gui) DISABLE_GUI=1 ;;
        --disable-x11) DISABLE_X11=1 ;;
        *) echo "[!] Unknown option '$1'"; show_usage; exit 1 ;;
    esac
    shift 1
done

TERMUX_GENERATOR_CONTAINER_NAME="$TERMUX_APP__PACKAGE_NAME-$TERMUX_APP_TYPE-package-builder"

if [ -z "${DO_NOT_CLEAN}" ]; then
    check_names
    clean_docker
    clean_artifacts
    download
    if [ -n "$TERMUX_GENERATOR_PLUGIN" ]; then
        install_plugin
    fi
    patch_bootstraps
    patch_apps
    if [ -z "${DISABLE_X11}" ]; then
        build_termux_x11
        move_termux_x11_deb
    fi
    if [ -z "${DISABLE_BOOTSTRAP}" ]; then
        build_bootstraps
        move_bootstraps
    fi
fi

if [[ "$TERMUX_APP_TYPE" == "f-droid" ]] || [ -z "${DISABLE_TERMINAL}" ]; then
    if [ -z "${DISABLE_X11}" ]; then
        build_termux_x11
    fi
    build_apps
    move_apks
fi

exit 0
