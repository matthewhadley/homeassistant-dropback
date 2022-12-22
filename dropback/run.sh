#!/usr/bin/with-contenv bashio

CONFIG_PATH=/data/options.json
OAUTH_APP_KEY="$(bashio::config 'oauth_app_key')"
OAUTH_APP_SECRET="$(bashio::config 'oauth_app_secret')"
OAUTH_ACCESS_CODE="$(bashio::config 'oauth_access_code')"
FOLDER="$(bashio::config 'folder')"
USE_BACKUP_NAMES="$(bashio::config 'use_backup_names')"
DELETE_OLDER_THAN="$(bashio::config 'delete_older_than')"
SYNC_DELETES="$(bashio::config 'sync_deletes')"

# remove extra slashes
FOLDER=$(echo "$FOLDER" | tr -s /)
BACKUP_DIR="/backup"
BACKUP_API="/backups"
CONFIG_FILE="/data/uploader.conf"
REQUIRED_SCOPE="files.content.write"
DROPBOX_ACCESS_TOKEN_URL="https://www.dropbox.com/oauth2/authorize?client_id=${OAUTH_APP_KEY}&token_access_type=offline&response_type=code"
DROPBOX_API_CHECK_URL="api.dropboxapi.com"
DROPBACK_VERSION=$(cat VERSION)


# add date to default bashio log timestamp
declare __BASHIO_LOG_TIMESTAMP="%Y-%m-%d %T"

warn_about_access_token() {
    bashio::log.fatal "Please check App Key and App Secret configuration values and generate a new Access Token"
    bashio::log.fatal "A new Access Token can be generated at: $DROPBOX_ACCESS_TOKEN_URL"
}

check_network_access() {
    EXIT_CODE=0
    curl --silent $DROPBOX_API_CHECK_URL || EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        bashio::log.fatal "Unable to reach $DROPBOX_API_CHECK_URL"
        [ $EXIT_CODE -eq 6 ] && bashio::log.fatal "Could not resolve host - is there a problem with the network?"
        [ $EXIT_CODE -eq 7 ] && bashio::log.fatal "Failed to connect to host - is there a problem with the network?"
    fi
    EXIT_CODE=0
}

bashio::log.info "Dropback $DROPBACK_VERSION"

# return the path a backup should exist on Dropbox
get_dropbox_file_path() {
    FILE=$1

    BASENAME=$(basename "$FILE")
    if [[ $USE_BACKUP_NAMES = "true" ]]; then
        SLUG="${BASENAME%.*}"
        EXT="${BASENAME##*.}"
        BACKUP_NAME=$(bashio::api.supervisor "GET" "$BACKUP_API/$SLUG/info" | jq -r .name)
        # if no backup name in metadata, use filename
        if [[ "$BACKUP_NAME" = "" ]]; then
            BACKUP_NAME=$SLUG
        fi
        echo "$FOLDER/$BACKUP_NAME.$EXT" | tr -s /
    else
        echo "$FOLDER/$BASENAME" | tr -s /
    fi
}

# create/update HASS entities
set_dropback_entity_status() {
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    curl --silent -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" http://supervisor/core/api/states/dropback.status -d '{"state":"'"$1"'", "attributes":{"friendly_name":"Dropback Status", "timestamp":"'"$timestamp"'"}}'
}
set_dropback_entity_sync() {
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    curl --silent -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" http://supervisor/core/api/states/dropback.sync -d '{"state":"'"$1"'", "attributes":{"friendly_name":"Dropback Sync", "timestamp":"'"$timestamp"'"}}'
}

# configure Dropbox access
bashio::log.info "Initializing Dropback"
set_dropback_entity_status "OK"
set_dropback_entity_sync "None"

if [ ! -e "$CONFIG_FILE" ]; then
    bashio::log.info "No config file found, requesting long lived Refresh Token..."

    check_network_access

    RESPONSE=$(curl https://api.dropbox.com/oauth2/token \
    -d grant_type=authorization_code \
    -u "$OAUTH_APP_KEY:$OAUTH_APP_SECRET" \
    -d code="$OAUTH_ACCESS_CODE" \
    --silent)

    OAUTH_REFRESH_TOKEN=$(echo "$RESPONSE" | jq -r .refresh_token)
    if [[ "$OAUTH_REFRESH_TOKEN" = "null" ]]; then
        # an error getting the Refresh Token
        ERROR=$(echo "$RESPONSE" | jq -r .error)
        ERROR_DESCRIPTION=$(echo "$RESPONSE" | jq -r .error_description)

        bashio::log.fatal "Error getting Refresh Token"
        bashio::log.fatal "$ERROR $ERROR_DESCRIPTION"
        warn_about_access_token
        set_dropback_entity_status "Error"
        bashio::exit.nok
    else
        # ensure app has correct permissions
        SCOPE=$(echo "$RESPONSE" | jq -r .scope)
        EXIT_CODE=0
        echo "$SCOPE" | grep -q "$REQUIRED_SCOPE" || EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
            bashio::log.fatal "Missing scope \"$REQUIRED_SCOPE\""
            bashio::log.fatal "Please ensure the app has scope \"$REQUIRED_SCOPE\" enabled in the \"Permissions\" tab on dropbox.com/developers/apps"
            warn_about_access_token
            set_dropback_entity_status "Error"
            bashio::exit.nok
        fi
    fi

    bashio::log.info "Got Refresh Token"
    echo "CONFIGFILE_VERSION=2.0" > "$CONFIG_FILE"
    echo "OAUTH_APP_KEY=$OAUTH_APP_KEY" >> "$CONFIG_FILE"
    echo "OAUTH_APP_SECRET=$OAUTH_APP_SECRET" >> "$CONFIG_FILE"
    echo "OAUTH_REFRESH_TOKEN=$OAUTH_REFRESH_TOKEN" >> "$CONFIG_FILE"
    bashio::log.info "Config file saved"
else
    bashio::log.info "Existing config file found"
fi

# validate Dropbox access
bashio::log.info "Validating Dropbox access... "

check_network_access

EXIT_CODE=0
RESPONSE=$(./dropbox_uploader.sh -q -f $CONFIG_FILE space) || EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    bashio::log.info "Dropbox access OK"
else
    bashio::log.fatal "Failed validating Dropbox access"
    [ "$RESPONSE" != "" ] && bashio::log.fatal "$RESPONSE"
    warn_about_access_token
    rm "$CONFIG_FILE"
    set_dropback_entity_status "Error"
    bashio::exit.nok
fi

# listen for input
bashio::log.info "Listening for input via stdin service call..."

while read -r INPUT; do
    # strip quotes
    INPUT=${INPUT:1:-1}
    bashio::log.info "Received input: $INPUT"

    if [[ "$INPUT" = "sync" ]]; then
        if [ -z "$(ls -A $BACKUP_DIR)" ]; then
            # dropbox_uploader will error when attempting to upload an empty dir
            bashio::log.info "No backups found, nothing to do"
        else
            # find files older than X days, delete locally and delete on dropbox
            if [[ $DELETE_OLDER_THAN != "0" ]]; then
                PLURAL=''
                [ "$DELETE_OLDER_THAN" != "1" ] && PLURAL='s'
                bashio::log.info "Deleting files older than $DELETE_OLDER_THAN day${PLURAL}..."
                # adjust DELETE_OLDER_THAN value down by 1 for correct mtime value
                find $BACKUP_DIR -maxdepth 1 -mtime +$(($DELETE_OLDER_THAN-1)) -type f -name "*.tar" -print0 |
                while IFS= read -r -d '' FILE; do
                    # get Dropbox file path to use to remove from Dropbox after local delete
                    if [[ $SYNC_DELETES = "true" ]]; then
                        FILE_PATH=$(get_dropbox_file_path "$FILE")
                    fi
                    bashio::log.info "Deleted local file $FILE"
                    rm "$FILE"
                    if [[ $SYNC_DELETES = "true" ]]; then
                        bashio::log.debug "Delete $FILE_PATH on Dropbox"
                        check_network_access
                        EXIT_CODE=0
                        RESPONSE=$(./dropbox_uploader.sh -q -f $CONFIG_FILE delete "$FILE_PATH") || EXIT_CODE=$?
                        if [ $EXIT_CODE -eq 0 ]; then
                            bashio::log.info "Deleted $FILE_PATH on Dropbox"
                        else
                            bashio::log.fatal "Failed to delete $FILE_PATH on Dropbox"
                            [ "$RESPONSE" != "" ] && bashio::log.fatal "$RESPONSE"
                        fi
                    fi
                    EXIT_CODE=0
                done
                bashio::log.info "Done with deletes"
            fi

            # find remaining files and sync to dropbox
            bashio::log.info "Syncing local files to Dropbox..."
            find $BACKUP_DIR -maxdepth 1 -type f -name "*.tar" -print0 |
            while IFS= read -r -d '' FILE; do
                FILE_PATH=$(get_dropbox_file_path "$FILE")
                set_dropback_entity_sync "${FILE_PATH/\//}"
                bashio::log.debug "Sync $FILE to $FILE_PATH on Dropbox"
                check_network_access
                EXIT_CODE=0
                RESPONSE=$(./dropbox_uploader.sh -q -s -f $CONFIG_FILE upload "$FILE" "$FILE_PATH") || EXIT_CODE=$?
                if [ $EXIT_CODE -eq 0 ]; then
                    bashio::log.info "Synced $FILE to $FILE_PATH on Dropbox"
                    set_dropback_entity_status "OK"
                else
                    bashio::log.fatal "Failed to sync $FILE to $FILE_PATH on Dropbox"
                    [ "$RESPONSE" != "" ] && bashio::log.fatal "$RESPONSE"
                    set_dropback_entity_status "Error"
                fi
                EXIT_CODE=0
            done
            bashio::log.info "Syncing done"
            set_dropback_entity_sync "None"

        fi
    else
        # received unknown input
        bashio::log.notice "Ignoring unknown input: $INPUT"
    fi

    bashio::log.info "Listening for input via stdin service call..."
done
