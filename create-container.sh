#!/usr/bin/env bash

textBold=$(tput bold)
textNormal=$(tput sgr0)

# 1. Set defaults for optional arguments

_lastLXCId=$(pct list | tail -n 1 | grep -Eo '^[[:digit:]]+' -)

LXC_ID=$((LAST_LXC_ID + 1))
LXC_TEMPLATE="local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
LXC_HOST_MNT="/mnt/shared"
LXC_GUEST_MNT="/mnt/shared"
LXC_VOLSIZE_GB=8
LXC_CPU_CORES=2
LXC_MEMORY_MB=2048

usage() {
    cat <<EOF
${textBold}SYNOPSIS${textNormal}
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
    printf "HOSTNAME is required\n"
    usage
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
            echo '--id requires a value'
            exit 1
        fi
        ;;
    --template)
        if [ "$2" ]; then
            LXC_TEMPLATE="$2"
            shift
        else
            echo '--template requires a value'
            exit 1
        fi
        ;;
    --host-mount)
        if [ "$2" ]; then
            LXC_HOST_MNT="$2"
            shift
        else
            echo '--host-mount requires a value'
            exit 1
        fi
        ;;
    --guest-mount)
        if [ "$2" ]; then
            LXC_GUEST_MNT="$2"
            shift
        else
            echo '--guest-mount requires a value'
            exit 1
        fi
        ;;
    --disk-size)
        if [ "$2" ]; then
            LXC_VOLSIZE_GB="$2"
            shift
        else
            echo '--disk-size requires a value'
            exit 1
        fi
        ;;
    --cpu-cores)
        if [ "$2" ]; then
            LXC_CPU_CORES="$2"
            shift
        else
            echo '--cpu-cores requires a value'
            exit 1
        fi
        ;;
    --memory-limit)
        if [ "$2" ]; then
            LXC_MEMORY_MB="$2"
            shift
        else
            echo '--memory-limit requires a value'
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
pct exec "$LXC_ID" -- groupadd -g 10000 nas_shares
pct exec "$LXC_ID" -- useradd "$LXC_HOSTNAME" -u 1000 -g 10000 -m -s /bin/bash

# 5. Install avahi-daemon
pct exec "$LXC_ID" apt install avahi-daemon

# 6. Set OS locale in container (optional)
pct enter "$LXC_ID"
dpkg-reconfigure locales
