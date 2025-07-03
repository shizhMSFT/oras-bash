#!/bin/bash

# oras-ext.sh - ORAS bash extension script based on the oras binary

# usage: oras backup [flags] <registry>/<repository>[:<ref1>[,<ref2>...]] [...]
# flags:
#   -o, --output <file>     Output path for the backup
#       --include-referrers Include referrers in the backup
function oras_backup() { ## Backup OCI artifacts and repositories from a registry
    local raw_ref=()
    local output=""
    local include_referrers=""

    # parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                output="$2"
                shift 2
                ;;
            --include-referrers)
                include_referrers="-r"
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                raw_ref+=("$1")
                shift
                ;;
        esac
    done
    
    # set up a temp output folder if output is a tarball
    local tar_output=""
    if [[ $output == *.tar ]]; then
        tar_output="$output"
        output=$(mktemp -d)
    fi

    # backup each repository
    local multi_repo=false
    if [[ ${#raw_ref[@]} -gt 1 ]]; then
        multi_repo=true
    fi
    for ref in "${raw_ref[@]}"; do
        # parse tags
        local full_repo=""
        local tags=""
        read full_repo tags <<< $(parse_ref "$ref")
        if [[ -z $tags ]]; then
            tags=$(oras repo tags $full_repo)
        fi
        echo "Backing up repository: $full_repo"
        echo "Tags:"
        for tag in $tags; do
            echo "- $tag"
        done

        # backup each tag
        for tag in $tags; do
            printf "\e[32m>>>\e[0m %s\n" "Backing up $full_repo:$tag"

            if $multi_repo; then
                oras cp $include_referrers --to-oci-layout-path "$output" "$full_repo:$tag" "$full_repo:$tag"
            else
                oras cp $include_referrers "$full_repo:$tag" --to-oci-layout "$output:$tag"
            fi
        done
    done

    # create a tarball if output is a tarball
    rm -r "$output/ingest" 2>/dev/null
    if [[ -n $tar_output ]]; then
        echo "Creating tarball: $tar_output"
        tar -cf "$tar_output" -C "$output" .
        rm -rf "$output"
        echo "Backup saved to a tarball: $tar_output"
    else
        echo "Backup saved to directory: $output"
    fi
}

function oras_help() { ## Show this help
    echo "ORAS bash extension script based on the oras binary"
    echo "Usage: $0 <command> [args]"
    echo "Commands:"
    grep -E '^function oras_[a-zA-Z0-9_-]+\(\) { ##' "$0" | sed 's/function oras_\(.*\)() { ## \(.*\)/\1|\2/g' | while IFS="|" read cmd desc; do
        cmd=${cmd//_/ }
        if [[ $desc == *" - "* ]]; then
            cmd+=" ${desc%% -*}"
            desc=${desc#*- }
        fi
        printf "  %-40s %s\n" "$cmd" "$desc"
    done
}

# Parse a reference string into full repository and tag
# Examples:
# "registry.example.com/repo"           -> "registry.example.com/repo"
# "registry.example.com/repo:tag1"      -> "registry.example.com/repo tag1"
# "registry.example.com/repo:tag1,tag2" -> "registry.example.com/repo tag1 tag2"
function parse_ref() {
    local ref="$1"
    local full_repo=""
    local tags=""

    if [[ $ref == *:* ]]; then
        full_repo=${ref%%:*}
        tags=${ref#*:}
        tags=${tags//,/ }
    else
        full_repo=$ref
    fi

    echo $full_repo $tags
}

cmd=$1
shift
if [[ -z $cmd ]]; then
    oras_help
    exit 1
fi
oras_$cmd "$@"
