#!/usr/bin/env bash

# This script vendors the Mutagen proto files from a tag on a Mutagen GitHub repo.
# It is very similar to `Update-Proto.ps1` on `coder/coder-desktop-windows`.
# It's very unlikely that we'll use this script regularly.
#
# Unlike the Go compiler, the Swift compiler does not support multiple files 
# with the same name in different directories. 
# To handle this, this script flattens the directory structure of the proto 
# files into the filename, i.e. `service/synchronization/synchronization.proto`
# becomes `service_synchronization_synchronization.proto`.
# It also updates the proto imports to use these paths.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <mutagen-tag>"
    exit 1
fi

mutagen_tag="$1"

# TODO: Change this to `coder/mutagen` once we add a version tag there
repo="mutagen-io/mutagen"
proto_prefix="pkg"
# Right now, we only care about the synchronization and daemon management gRPC
entry_files=("service/synchronization/synchronization.proto" "service/daemon/daemon.proto")

out_folder="Coder-Desktop/VPNLib/FileSync/MutagenSDK"

clone_dir="/tmp/coder-desktop-mutagen-proto"
if [ -d "$clone_dir" ]; then
    echo "Found existing mutagen repo at $clone_dir, checking out $mutagen_tag..."
    pushd "$clone_dir" > /dev/null
    git clean -fdx
    
    current_tag=$(git name-rev --name-only HEAD)
    if [ "$current_tag" != "tags/$mutagen_tag" ]; then
        git fetch --all
        git checkout "$mutagen_tag"
    fi
    popd > /dev/null
else
    mkdir -p "$clone_dir"
    echo "Cloning mutagen repo to $clone_dir..."
    git clone --depth 1 --branch "$mutagen_tag" "https://github.com/$repo.git" "$clone_dir"
fi

# Extract MIT License header
mit_start_line=$(grep -n "^MIT License" "$clone_dir/LICENSE" | cut -d ":" -f 1)
if [ -z "$mit_start_line" ]; then
    echo "Failed to find MIT License header in Mutagen LICENSE file"
    exit 1
fi
license_header=$(sed -n "${mit_start_line},\$p" "$clone_dir/LICENSE" | sed 's/^/ * /')

declare -A file_map=()
file_paths=()

add_file() {
    local filepath="$1"
    local proto_path="${filepath#"$clone_dir"/"$proto_prefix"/}"
    local flat_name
    flat_name=$(echo "$proto_path" | sed 's/\//_/g')
    
    # Skip if already processed
    if [[ -n "${file_map[$proto_path]:-}" ]]; then
        return
    fi
    
    echo "Adding $proto_path -> $flat_name"
    file_map[$proto_path]=$flat_name
    file_paths+=("$filepath")
    
    # Process imports
    while IFS= read -r line; do
        if [[ $line =~ ^import\ \"(.+)\" ]]; then
            import_path="${BASH_REMATCH[1]}"
            
            # Ignore google imports, as they're not vendored
            if [[ $import_path =~ ^google/ ]]; then
                echo "Skipping $import_path"
                continue
            fi
            
            import_file_path="$clone_dir/$proto_prefix/$import_path"
            if [ -f "$import_file_path" ]; then
                add_file "$import_file_path"
            else
                echo "Warning: Import $import_path not found"
            fi
        fi
    done < "$filepath"
}

for entry_file in "${entry_files[@]}"; do
    entry_file_path="$clone_dir/$proto_prefix/$entry_file"
    if [ ! -f "$entry_file_path" ]; then
        echo "Failed to find $entry_file_path in mutagen repo"
        exit 1
    fi
    add_file "$entry_file_path"
done

mkdir -p "$out_folder"

for file_path in "${file_paths[@]}"; do
    proto_path="${file_path#"$clone_dir"/"$proto_prefix"/}"
    flat_name="${file_map[$proto_path]}"
    dst_path="$out_folder/$flat_name"
    
    cp -f "$file_path" "$dst_path"
    
    file_header="/*\n * This file was taken from\n * https://github.com/$repo/tree/$mutagen_tag/$proto_prefix/$proto_path\n *\n$license_header\n */\n\n"
    content=$(cat "$dst_path")
    echo -e "$file_header$content" > "$dst_path"
    
    tmp_file=$(mktemp)
    while IFS= read -r line; do
        if [[ $line =~ ^import\ \"(.+)\" ]]; then
            import_path="${BASH_REMATCH[1]}"
            
            # Retain google imports
            if [[ $import_path =~ ^google/ ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi
            
            # Convert import path to flattened format
            flat_import=$(echo "$import_path" | sed 's/\//_/g')
            echo "import \"$flat_import\";" >> "$tmp_file"
        else
            echo "$line" >> "$tmp_file"
        fi
    done < "$dst_path"
    mv "$tmp_file" "$dst_path"
    
    echo "Processed $proto_path -> $flat_name"
done

echo "Successfully downloaded proto files from $mutagen_tag to $out_folder"