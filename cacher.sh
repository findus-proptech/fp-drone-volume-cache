#!/bin/bash
set -e


if [[ -n "$PLUGIN_VERBOSE" && "$PLUGIN_VERBOSE" == "true" ]]; then
  echo "========== drone values ========="
  echo "DRONE_REPO_OWNER: ${DRONE_REPO_OWNER}"
  echo "DRONE_REPO_NAME: ${DRONE_REPO_NAME}"
  echo "DRONE_BRANCH: ${DRONE_BRANCH}"
  echo "DRONE_JOB_NUMBER: ${DRONE_JOB_NUMBER}"
  echo "DRONE_COMMIT_MESSAGE: ${DRONE_COMMIT_MESSAGE}"
  echo
  echo "========== plugin settings ========="
  echo "PLUGIN_VERBOSE: ${PLUGIN_VERBOSE}"
  echo "PLUGIN_CACHE_KEY: ${PLUGIN_CACHE_KEY}"
  echo "PLUGIN_MOUNT: ${PLUGIN_MOUNT}"
  echo "PLUGIN_RESTORE: ${PLUGIN_RESTORE}"
  echo "PLUGIN_REBUILD: ${PLUGIN_REBUILD}"
  echo "PLUGIN_TTL: ${PLUGIN_TTL}"
fi

if [ -z "$PLUGIN_MOUNT" ]; then
    echo "Specify folders to cache in the mount property! Plugin won't do anything!"
    exit 0
fi

if [[ $DRONE_COMMIT_MESSAGE == *"[NO CACHE]"* ]]; then
    echo "Found [NO CACHE] in commit message, skipping cache restore and rebuild!"
    exit 0
fi

CACHE_PATH="$DRONE_REPO_OWNER/$DRONE_REPO_NAME/$DRONE_JOB_NUMBER"
if [[ -n "$PLUGIN_CACHE_KEY" ]]; then
    function join_by { local IFS="$1"; shift; echo "$*"; }
    IFS=','; read -ra CACHE_PATH_VARS <<< "$PLUGIN_CACHE_KEY"
    CACHE_PATH_VALUES=()
    for env_var in "${CACHE_PATH_VARS[@]}"; do
        env_var_value="${!env_var}"

        if [[ -z "$env_var_value" ]]; then
            echo "Warning! Environment variable '${env_var}' does not contain a value, it will be ignored!"
        else
            CACHE_PATH_VALUES+=("${env_var_value}")
        fi
    done
    CACHE_PATH=$(join_by / "${CACHE_PATH_VALUES[@]}")
fi

if [[ -e ".cache_key" ]]; then
    echo "Found a .cache_key file to be used as the cache path!"
    CACHE_PATH=$(cut -c-$(getconf NAME_MAX /) .cache_key | head -n 1)

    if [[ -n "$PLUGIN_CACHE_KEY_DISABLE_SANITIZE" && "$PLUGIN_CACHE_KEY_DISABLE_SANITIZE" == "true" ]]; then
        echo "Warning! .cache_key will be used as-is. Sanitization is your responsibility to make it filename friendly!"
    else
        CACHE_PATH=$(echo "$CACHE_PATH" | md5sum | cut -d ' ' -f 1)
    fi
fi

if [[ -n "$PLUGIN_VERBOSE" && "$PLUGIN_VERBOSE" == "true" ]]; then
  echo "CACHE_PATH: $CACHE_PATH"
  echo
fi

IFS=','; read -ra SOURCES <<< "$PLUGIN_MOUNT"
if [[ -n "$PLUGIN_REBUILD" && "$PLUGIN_REBUILD" == "true" ]]; then
    if [[ -n "$PLUGIN_VERBOSE" && "$PLUGIN_VERBOSE" == "true" ]]; then
      echo "========== rebuild sources =========="
    fi
    # Create cache
    for source in "${SOURCES[@]}"; do
        IFS=":" read -r path_container path_host <<< "$source"

        if [[ "$path_host" == /* ]]; then
            path_host="/cache/${CACHE_PATH}/${path_host:1}"
        elif [[ "$var" == ./* ]]; then
            path_host="/cache/${CACHE_PATH}/${path_host:2}"
        else
            path_host="/cache/${CACHE_PATH}/$path_host"
        fi

        if [[ "$path_container" == /* ]]; then
            path_container=$path_container
        elif [[ "$var" == ./* ]]; then
            path_container="$(pwd)/${path_container:2}"
        else
            path_container="$(pwd)/$path_container"
        fi

        if [[ -n "$PLUGIN_VERBOSE" && "$PLUGIN_VERBOSE" == "true" ]]; then
          echo
          echo "---------------------------------"
          echo "source: ${source}"
          echo "path_host: ${path_host}"
          echo "path_container: ${path_container}"
        fi

        if [ -d "$path_container" ]; then
          echo "Rebuilding cache for folder $path_container (container) to ${path_host} (host) ..."
            mkdir -p "$path_host" && \
                rsync -aHA --delete "$path_container/" "$path_host"
        elif [ -f "$path_container" ]; then
            echo "Rebuilding cache for file $path_container (container) to ${path_host} (host) ..."
            mkdir -p "$path_host" && \
              rsync -aHA --delete "$path_container" "$path_host/"
        else
            echo "$path_container does not exist, removing from cached folder..."
            rm -rf "${path_host}"
        fi
    done
elif [[ -n "$PLUGIN_RESTORE" && "$PLUGIN_RESTORE" == "true" ]]; then
    # Clear existing cache if asked in commit message
    if [[ $DRONE_COMMIT_MESSAGE == *"[CLEAR CACHE]"* ]]; then
        if [ -d "/cache/$CACHE_PATH" ]; then
            echo "Found [CLEAR CACHE] in commit message, clearing cache..."
            rm -rf "/cache/$CACHE_PATH"
            exit 0
        fi
    fi
    # Remove files older than TTL
    if [[ -n "$PLUGIN_TTL" && "$PLUGIN_TTL" > "0" ]]; then
        if [[ $PLUGIN_TTL =~ ^[0-9]+$ ]]; then
            if [ -d "/cache/$CACHE_PATH" ]; then
              echo "Removing files and (empty) folders older than $PLUGIN_TTL days..."
              find "/cache/$CACHE_PATH" -type f -ctime +$PLUGIN_TTL -delete
              find "/cache/$CACHE_PATH" -type d -ctime +$PLUGIN_TTL -empty -delete
            fi
        else
            echo "Invalid value for ttl, please enter a positive integer. Plugin will ignore ttl."
        fi
    fi
    # Restore from cache
    for source in "${SOURCES[@]}"; do
        echo "source: ${source}"
        IFS=":" read -r dir_host_cache dir_container <<< "$source"
        # Remove leading ./ if present
        path_container=$(pwd)/${dir_container#./}
        path_host_cache=/cache/${CACHE_PATH}/${dir_host_cache#./}
        echo "path_container: ${path_container}"
        echo "path_host_cache: ${path_host_cache}"
        echo "pwd: $(pwd)"
        if [ -d "$path_host_cache" ]; then
            echo "Restoring cache for dir $path_host_cache (host) to $path_container (container)"
            mkdir -p "$path_container" && \
                rsync -aHA --delete "$path_host_cache/" "$path_container"
        elif [ -f "$path_host_cache" ]; then
            echo "Restoring cache for file $path_host_cache (host) to $path_container (container)"
            mkdir -p "$path_container" && \
                rsync -aHA --delete "$path_host_cache" "$path_container/"
        else
            echo "No cache for $path_host_cache"
        fi
    done
else
    echo "No restore or rebuild flag specified, plugin won't do anything!"
fi
