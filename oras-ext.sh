#!/bin/bash

# oras-ext.sh - ORAS bash extension script based on the oras binary

# usage: oras backup [flags] <registry>/<repository>[:<ref1>[,<ref2>...]] [...]
# flags:
#   -o, --output <path>     Output path for the backup
#       --include-referrers Include referrers in the backup
function oras_backup() { ## Backup OCI artifacts and repositories from a registry
    local raw_refs=()
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
                raw_refs+=("$1")
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
    if [[ ${#raw_refs[@]} -gt 1 ]]; then
        multi_repo=true
    fi
    for raw_ref in "${raw_refs[@]}"; do
        # parse tags
        local full_repo=""
        local tags=""
        read full_repo tags <<< $(parse_ref "$raw_ref")
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
            ref="$full_repo:$tag"
            printf "\e[32m>>>\e[0m %s\n" "Backing up $ref"

            if $multi_repo; then
                oras cp $include_referrers "$ref" --to-oci-layout-path "$output" "$ref"
            else
                oras cp $include_referrers "$ref" --to-oci-layout "$output:$tag"
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

# usage: oras restore [flags] <registry>/<repository>[:<ref1>[,<ref2>...]] [...]
# flags:
#   -i, --input <path>      Input path for the backup
#       --exclude-referrers Exclude referrers from the restore
function oras_restore() { ## Restore OCI artifacts and repositories from a backup
    local raw_refs=()
    local input=""
    local exclude_referrers="-r"

    # parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input="$2"
                shift 2
                ;;
            --exclude-referrers)
                exclude_referrers=""
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                exit 1
                ;;
            *)
                raw_refs+=("$1")
                shift
                ;;
        esac
    done

    # check if the source input is a multi-repository layout
    local all_tags=$(oras repo tags --oci-layout "$input")
    local multi_repo=false
    if grep -q ':' <<< "$all_tags"; then
        multi_repo=true
    fi

    # restore each repository
    for raw_ref in "${raw_refs[@]}"; do
        # parse tags
        local full_repo=""
        local tags=""
        read full_repo tags <<< $(parse_ref "$raw_ref")
        if [[ -z $tags ]]; then
            if $multi_repo; then
                tags=$(grep "$full_repo:" <<< "$all_tags")
            else
                tags=$all_tags
            fi
        fi

        echo "Restoring repository: $full_repo"
        echo "Tags:"
        for tag in $tags; do
            tag=${tag#"$full_repo:"}
            echo "- $tag"
        done

        # restore each tag
        for tag in $tags; do
            if [[ $tag == *:* ]]; then
                tag=${tag#"$full_repo:"}
            fi

            ref="$full_repo:$tag"
            printf "\e[32m>>>\e[0m %s\n" "Restoring $ref"

            if $multi_repo; then
                echo oras cp $exclude_referrers --from-oci-layout-path "$input" "$ref" "$ref"
            else
                echo oras cp $exclude_referrers --from-oci-layout "$input:$tag" "$ref"
            fi
        done
    done

    echo "Restored from $input"
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
