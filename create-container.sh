#!/usr/bin/env bash

set -o errexit

textRed=$(tput setaf 1)
textBold=$(tput bold)
textItalics=$(tput sitm)
textNormal=$(tput sgr0)

log_info() {
    printf '\n%s%s%s\n' "$textBold" "$1" "$textNormal"
}

log_error() {
    log_info "$textRed$1"
}

confirm_action() {
    while true; do
        read -r -n1 -p "${textBold}Do you want to proceed? [y,n]${textNormal} " response

        case "$response" in
        y | Y)
            true
            return
            ;;
        n | N)
            false
            return 1
            ;;
        *)
            log_error 'Please provide a valid answer'
            continue
            ;;
        esac
    done
}

# 1. Set defaults for optional arguments

_lastLXCId=$(pct list | tail -n 1 | grep -Eo '^[[:digit:]]+' -)

LXC_ID=$((_lastLXCId + 1))
LXC_TEMPLATE="local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
LXC_HOST_MNT="/mnt/shared"
LXC_GUEST_MNT="/mnt/shared"
LXC_VOLSIZE_GB=8
LXC_CPU_CORES=2
LXC_MEMORY_MB=2048

usage() {
    cat <<EOF
${textBold}USAGE${textNormal}
    $0 <HOSTNAME> [OPTIONS]

${textBold}DESCRIPTION${textNormal}
    Convenience script to create proxmox containers (LXC) from pve host.

${textBold}HOSTNAME${textNormal}
    Hostname for the created container (tip: use kebab-case)

${textBold}OPTIONS${textNormal}
    --id
        Id of new container (default: '$LXC_ID')

    --template
        OS template to use (default: '$LXC_TEMPLATE')

    --host-mount
        Path to host storage resource to mount in guest (default: '$LXC_HOST_MNT')

    --guest-mount
        Where in new container (path) to mount the --host-mount resource (default: '$LXC_GUEST_MNT')

    --disk-size
        Amount of GBs to allocate to container volume (default: '$LXC_VOLSIZE_GB')

    --cpu-cores
        Number of CPU cores container is allowed to use (default: '$LXC_CPU_CORES')

    --memory-limit
        Maximum amount of memory (in MB) container is allowed to use (default: '$LXC_MEMORY_MB')

    -h | --help
        Show this message
EOF
}

# 2. Read arguments/options
LXC_HOSTNAME=$1

if [[ -z "$LXC_HOSTNAME" ]]; then
    log_error 'ERROR: Please provide a hostname.'
    log_info 'See --help for more info.'
    exit 1
fi

shift # The shift keyword moves all the parameters forward one, so $2 becomes $1, and $3 becomes $2, etc.

while [ ! $# -eq 0 ]; do
    case "$1" in
    --id)
        if [ "$2" ]; then
            LXC_ID="$2"
            shift
        else
            log_error 'ERROR: --id requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --template)
        if [ "$2" ]; then
            LXC_TEMPLATE="$2"
            shift
        else
            log_error 'ERROR: --template requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --host-mount)
        if [ "$2" ]; then
            LXC_HOST_MNT="$2"
            shift
        else
            log_error 'ERROR: --host-mount requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --guest-mount)
        if [ "$2" ]; then
            LXC_GUEST_MNT="$2"
            shift
        else
            log_error 'ERROR: --guest-mount requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --disk-size)
        if [ "$2" ]; then
            LXC_VOLSIZE_GB="$2"
            shift
        else
            log_error 'ERROR: --disk-size requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --cpu-cores)
        if [ "$2" ]; then
            LXC_CPU_CORES="$2"
            shift
        else
            log_error 'ERROR: --cpu-cores requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    --memory-limit)
        if [ "$2" ]; then
            LXC_MEMORY_MB="$2"
            shift
        else
            log_error 'ERROR: --memory-limit requires a value'
            log_info 'See --help for more info.'
            exit 1
        fi
        ;;
    -h | --help)
        usage
        exit
        ;;
    *)
        usage
        exit
        ;;
    esac
    shift
done

# 3. Create container with provided hostname and optionally provided options

log_info "
Container will be created with these parameters:${textNormal}
    HOSTNAME:   ${textItalics}$LXC_HOSTNAME${textNormal}
    ID:         ${textItalics}$LXC_ID${textNormal}
    TEMPLATE:   ${textItalics}$LXC_TEMPLATE${textNormal}
    HOST_MNT:   ${textItalics}$LXC_HOST_MNT${textNormal}
    GUEST_MNT:  ${textItalics}$LXC_GUEST_MNT${textNormal}
    VOLSIZE_GB: ${textItalics}$LXC_VOLSIZE_GB${textNormal}
    CPU_CORES:  ${textItalics}$LXC_CPU_CORES${textNormal}
    MEMORY_MB:  ${textItalics}$LXC_MEMORY_MB${textNormal}
"

if ! confirm_action; then
    log_info 'User chose not to proceed. Exiting...'
    exit 0
fi

# Echo commands during execution (except those whitelisted)
# See: https://unix.stackexchange.com/a/725182
set -T
trap '! [[ "$BASH_COMMAND" =~ ^(echo|printf|log_) ]] &&
    printf "+ %s\n" "$BASH_COMMAND"' DEBUG

log_info 'Creating new container…'
pct create "$LXC_ID" "$LXC_TEMPLATE" \
    --hostname "$LXC_HOSTNAME" \
    --cores "$LXC_CPU_CORES" \
    --memory "$LXC_MEMORY_MB" \
    --swap "$LXC_MEMORY_MB" \
    --net0 "name=eth0,firewall=1,ip=192.168.1.$LXC_ID/24,gw=192.168.1.1,bridge=vmbr0,type=veth" \
    --onboot 1 \
    --ostype debian \
    --rootfs "local-lvm:$LXC_VOLSIZE_GB" \
    --mp0 "$LXC_HOST_MNT,mp=$LXC_GUEST_MNT" \
    --start 1 \
    --features nesting=1 \
    --password "" # Prompts user for password

# 4. Add nas_share user

log_info "Adding nas_share user '$LXC_HOSTNAME'…"
pct exec "$LXC_ID" -- groupadd -g 10000 nas_shares
pct exec "$LXC_ID" -- useradd "$LXC_HOSTNAME" -u 1000 -g 10000 -m -s /bin/bash

# 5. Install avahi-daemon
log_info 'Installing avahi-daemon…'
pct exec "$LXC_ID" apt install avahi-daemon

# 6. Set OS locale in container (optional)
log_info 'Configuring OS locales…'
pct exec "$LXC_ID" -- \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen &&
    dpkg-reconfigure --frontend=noninteractive locales &&
    update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8
