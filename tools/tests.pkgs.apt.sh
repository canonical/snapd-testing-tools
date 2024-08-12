#!/bin/bash

remap_one() {
    case "$1" in
        man)
            if os.query is-debian; then
                echo "man-db"
            else
                echo "$1"
            fi
            ;;
        printer-driver-cups-pdf)
            if os.query is-debian || os.query is-trusty; then
                echo "cups-pdf"
            else
                echo "$1"
            fi
            ;;
        test-snapd-pkg-1)
            echo "curseofwar"
            ;;
        test-snapd-pkg-2)
            echo "robotfindskitten"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

cmd_install() {
    apt-get update

    local APT_FLAGS="--yes"
    while [ -n "$1" ]; do
        case "$1" in
            --no-install-recommends)
                APT_FLAGS="$APT_FLAGS --no-install-recommends"
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    # shellcheck disable=SC2086
    apt-get install $APT_FLAGS "$@"
}

cmd_is_installed() {
    dpkg -S "$1" >/dev/null 2>&1
}

cmd_query() {
    apt-cache policy "$1"
}

cmd_list_installed() {
    apt list --installed | cut -d ' ' -f 1,3 | sed -e 's@/.*\s@:@g' | sort
}

cmd_remove() {
    # Allow removing essential packages, that may get installed when using i386
    # packages on amd64 system. Normally they would be really essential but in
    # this case they are not really as essential.
    apt-get remove --yes --allow-remove-essential "$@"
}
