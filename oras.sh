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
    local scheme=$(get_scheme "$reg")

    $curl -L "$scheme://$reg/v2/$repo/blobs/$digest" "$@"
}

function oras_blob_push() {
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

function oras_ping() {
    local reg=$1
    local scheme=$(get_scheme "$reg")

    $curl -Ls "$scheme://$reg/v2/" | jq
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
    local scheme=$(get_scheme "$reg")
    $curl -Ls "$scheme://$reg/v2/_catalog" | jq -r '.repositories[]' | sort
}

function oras_repo_tags() {
    local ref=$1
    local reg=${ref%%/*}
    local repo=${ref#*/}
    local scheme=$(get_scheme "$reg")
    $curl -Ls "$scheme://$reg/v2/$repo/tags/list" | jq -r '.tags[]' | sort
}

function oras_test() {
    local cmd=$1
    shift
    case $cmd in
        chunked-upload)
            oras_test_chunked_upload "$@"
            ;;
        *)
            echo "Unknown command: $cmd"
            exit 1
            ;;
    esac
}

function oras_test_chunked_upload() {
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

function usage() {
    echo "Usage: $0 <command> [args]"
    echo "Commands:"
    echo "  blob fetch <ref> <file>"
    echo "  blob push <ref> <file>"
    echo "  manifest fetch <ref>"
    echo "  ping <registry>"
    echo "  repo ls <registry>"
    echo "  repo tags <ref>"
    echo "  test chunked-upload <ref> <file>"
    echo "  version"
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
    usage
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
    ping)
        oras_ping "$@"
        ;;
    repo)
        oras_repo "$@"
        ;;
    test)
        oras_test "$@"
        ;;
    version)
        echo "oras.sh v0.1.0"
        ;;
    *)
        echo "Unknown command: $cmd"
        exit 1
        ;;
esac
