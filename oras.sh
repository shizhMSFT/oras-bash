#!/bin/bash -e

function oras_blob() {
    local cmd=$1
    shift
    case $cmd in
        fetch)
            oras_blob_fetch "$@"
            ;;
        push)
            oras_blob_push "$@"
            ;;
        *)
            echo "Unknown command: $cmd"
            exit 1
            ;;
    esac
}

function oras_blob_fetch() {
    local ref=$1
    shift
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local digest=${repo#*@}
    repo=${repo%%@*}

    $curl -L "https://$reg/v2/$repo/blobs/$digest" "$@"
}

function oras_blob_push() {
    echo "not implemented"
}

function oras_manifest() {
    local cmd=$1
    shift
    case $cmd in
        fetch)
            oras_manifest_fetch "$@"
            ;;
        *)
            echo "Unknown command: $cmd"
            exit 1
            ;;
    esac
}

function oras_manifest_fetch() {
    local ref=$1
    shift
    local reg=${ref%%/*}
    local repo=${ref#*/}
    if [[ $repo == *@* ]]; then
        ref=${repo#*@}
        repo=${repo%%@*}
    else
        ref=${repo#*\:}
        repo=${repo%%\:*}
    fi

    local media_types=(
        "application/vnd.docker.distribution.manifest.v2+json"
        "application/vnd.docker.distribution.manifest.list.v2+json"
        "application/vnd.oci.image.manifest.v1+json"
        "application/vnd.oci.image.index.v1+json"
        "application/vnd.oci.artifact.manifest.v1+json"
    )
    local IFS=","
    $curl -LsH "Accept: ${media_types[*]}" "https://$reg/v2/$repo/manifests/$ref" | jq
}

function oras_repo() {
    local cmd=$1
    shift
    case $cmd in
        ls)
            oras_repo_ls "$@"
            ;;
        tags)
            oras_repo_tags "$@"
            ;;
        *)
            echo "Unknown command: $cmd"
            exit 1
            ;;
    esac
}

function oras_repo_ls() {
    local reg=$1
    $curl -Ls "https://$reg/v2/_catalog" | jq -r '.repositories[]' | sort
}

function oras_repo_tags() {
    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    $curl -Ls "https://$reg/v2/$repo/tags/list" | jq -r '.tags[]' | sort
}

curl="curl"
if [ -n "$ORAS_AUTH" ]; then
    curl+=" -u $ORAS_AUTH"
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [args]"
    exit 1
fi

cmd=$1
shift
case $cmd in
    blob)
        oras_blob "$@"
        ;;
    manifest)
        oras_manifest "$@"
        ;;
    repo)
        oras_repo "$@"
        ;;
    *)
        echo "Unknown command: $cmd"
        exit 1
        ;;
esac
