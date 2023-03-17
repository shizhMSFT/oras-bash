#!/bin/bash -e

function oras_blob() {
    local cmd=$1
    shift
    oras_blob_$cmd "$@"
}

function oras_blob_fetch() { ## <ref> - Fetch a blob from a registry
    local ref=$1
    shift
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local digest=${repo#*@}
    repo=${repo%%@*}
    local scheme=$(get_scheme "$reg")

    $curl -L "$scheme://$reg/v2/$repo/blobs/$digest" "$@"
}

function oras_blob_push() { ## <ref> <file> - Push a blob to a registry
    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local scheme=$(get_scheme "$reg")
    local file=$2
    local digest="sha256:$(sha256sum "$file" | cut -d" " -f1 | tr -d "\r")"

    # start an upload
    local upload_url=$($curl -s "$scheme://$reg/v2/$repo/blobs/uploads/" -XPOST -I | grep -i location | cut -d" " -f2 | tr -d "\r")
    if [[ $upload_url == /* ]]; then
        upload_url="$scheme://$reg$upload_url"
    fi

    # monolithic upload
    $curl -XPUT -H "Content-Type: application/octet-stream" --data-binary "@$file" "$upload_url&digest=$digest"

    echo "Pushed $reg/$repo"
    echo "Digest: $digest"
}

function oras_help() { ## Show this help
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

function oras_manifest() {
    local cmd=$1
    shift
    oras_manifest_$cmd "$@"
}

function oras_manifest_fetch() { ## <ref> - Fetch a manifest from a registry
    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    if [[ $repo == *@* ]]; then
        ref=${repo#*@}
        repo=${repo%%@*}
    else
        ref=${repo#*\:}
        repo=${repo%%\:*}
    fi
    local scheme=$(get_scheme "$reg")

    local media_types=(
        "application/vnd.docker.distribution.manifest.v2+json"
        "application/vnd.docker.distribution.manifest.list.v2+json"
        "application/vnd.oci.image.manifest.v1+json"
        "application/vnd.oci.image.index.v1+json"
        "application/vnd.oci.artifact.manifest.v1+json"
    )
    local IFS=","
    $curl -LsH "Accept: ${media_types[*]}" "$scheme://$reg/v2/$repo/manifests/$ref" | jq
}

function oras_ping() { ## <registry> - Ping a registry
    local reg=$1
    local scheme=$(get_scheme "$reg")

    $curl -Ls "$scheme://$reg/v2/" | jq
}

function oras_repo() {
    local cmd=$1
    shift
    oras_repo_$cmd "$@"
}

function oras_repo_ls() { ## <registry> - List repositories in a registry
    local reg=$1
    local scheme=$(get_scheme "$reg")
    $curl -Ls "$scheme://$reg/v2/_catalog" | jq -r '.repositories[]' | sort
}

function oras_repo_tags() { ## <ref> - List tags in a repository
    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local scheme=$(get_scheme "$reg")
    $curl -Ls "$scheme://$reg/v2/$repo/tags/list" | jq -r '.tags[]' | sort
}

function oras_test() {
    local cmd=$1
    shift
    oras_test_$cmd "$@"
}

function oras_test_chunked-upload() { ## <ref> <file> - Test blob chunked upload
    echo "---------------------------"
    echo "Testing blob chunked upload"
    echo "---------------------------"

    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local scheme=$(get_scheme "$reg")
    local file=$2
    local digest="sha256:$(sha256sum "$file" | cut -d" " -f1 | tr -d "\r")"
    echo "$file: digest: $digest: size: $(stat -c%s "$file")"

    # start an upload
    printf "\e[31m%s\e[0m\n" ">>> start upload"
    resp=$($curl -s "$scheme://$reg/v2/$repo/blobs/uploads/" -XPOST -I)
    local upload_url=$(echo "$resp" | grep -i location | cut -d" " -f2 | tr -d "\r")
    if [[ $upload_url == /* ]]; then
        upload_url="$scheme://$reg$upload_url"
    fi
    local uuid=$(echo "$resp" | grep -i docker-upload-uuid | cut -d" " -f2 | tr -d "\r")
    echo "UUID: $uuid"

    # chunked upload
    printf "\e[31m%s\e[0m\n" ">>> chunked upload"
    echo "Location: $upload_url"
    resp=$($curl -XPATCH -H "Content-Type: application/octet-stream" --data-binary "@$file" "$upload_url" -sD-)
    upload_url=$(echo "$resp" | grep -i location | cut -d" " -f2 | tr -d "\r")
    if [[ $upload_url == /* ]]; then
        upload_url="$scheme://$reg$upload_url"
    fi

    printf "\e[31m%s\e[0m\n" ">>> upload status"
    printf "\e[33m%s\e[0m\n" ">>> try /v2/$repo/blobs/uploads/$uuid"
    $curl "$scheme://$reg/v2/$repo/blobs/uploads/$uuid" -D-
    printf "\e[33m%s\e[0m\n" ">>> try $upload_url"
    $curl "$upload_url" -D-

    # commit
    printf "\e[31m%s\e[0m\n" ">>> commit"
    $curl -XPUT -H "Content-Type: application/octet-stream" "$upload_url&digest=$digest" -D-
}

function oras_version() { ## Show version
    echo "oras.sh v0.1.0"
}

function get_scheme() {
    local reg=$1
    if [[ $reg == localhost:* ]]; then
        echo "http"
    else
        echo "https"
    fi
}

curl="curl"
if [ -n "$ORAS_AUTH" ]; then
    curl+=" -u $ORAS_AUTH"
fi

if [ $# -lt 1 ]; then
    oras_help
    exit 1
fi

cmd=$1
shift
oras_$cmd "$@"
