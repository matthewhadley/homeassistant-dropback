#!/usr/bin/with-contenv bashio

CONFIG_PATH=/data/options.json
OAUTH_APP_KEY="$(bashio::config 'oauth_app_key')"
OAUTH_APP_SECRET="$(bashio::config 'oauth_app_secret')"
OAUTH_ACCESS_CODE="$(bashio::config 'oauth_access_code')"
FOLDER="$(bashio::config 'folder')"
DELETE_OLDER_THAN="$(bashio::config 'delete_older_than')"
SYNC_DELETES="$(bashio::config 'sync_deletes')"

# remove extra slashes
FOLDER=$(echo "$FOLDER" | tr -s /)
BACKUP_DIR="/backup"
CONFIG_FILE="/data/uploader.conf"

bashio::log.info "Initializing Dropback"

if [ ! -e "$CONFIG_FILE" ]; then
    bashio::log.info "No config file found, requesting long lived Refresh Token..."
    OAUTH_REFRESH_TOKEN=$(curl https://api.dropbox.com/oauth2/token \
    -d grant_type=authorization_code \
    -u "$OAUTH_APP_KEY:$OAUTH_APP_SECRET" \
    -d code="$OAUTH_ACCESS_CODE" \
    --silent | jq -r .refresh_token)

    if [[ "$OAUTH_REFRESH_TOKEN" = "null" ]]; then
        bashio::log.fatal "Error getting Refresh Token"
        bashio::log.fatal "Please check App Key and App Secret configuration values and generate a new Access Token"
        bashio::exit.nok
    else
        bashio::log.info "Got Refresh Token"
    fi

    echo "CONFIGFILE_VERSION=2.0" > "$CONFIG_FILE"
    echo "OAUTH_APP_KEY=$OAUTH_APP_KEY" >> "$CONFIG_FILE"
    echo "OAUTH_APP_SECRET=$OAUTH_APP_SECRET" >> "$CONFIG_FILE"
    echo "OAUTH_REFRESH_TOKEN=$OAUTH_REFRESH_TOKEN" >> "$CONFIG_FILE"
    bashio::log.info "Config file saved"
else
    bashio::log.info "Existing config file found"
fi

bashio::log.info "Validating Dropbox access... "
EXIT_CODE=0
./dropbox_uploader.sh -q -f $CONFIG_FILE space > /dev/null || EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    bashio::log.info "Dropbox access OK"
else
    bashio::log.fatal "Failed validating Dropbox access"
    bashio::log.fatal "Please check App Key and App Secret configuration values and generate a new Access Token"
    rm "$CONFIG_FILE"
    bashio::exit.nok
fi

bashio::log.info "Listening for input via stdin service call..."

# listen for input
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
                bashio::log.info "Deleting files older than $DELETE_OLDER_THAN day(s)"
                # adjust DELETE_OLDER_THAN value down by 1 for correct mtime value
                find $BACKUP_DIR -maxdepth 1 -mtime +$(($DELETE_OLDER_THAN-1)) -type f -name "*.tar" -print0 |
                while IFS= read -r -d '' FILE; do
                    rm "$FILE"
                    bashio::log.info "Deleted local file $FILE"
                    if [[ $SYNC_DELETES = "true" ]]; then
                        BASENAME=$(basename "$FILE")
                        FILE_PATH=$(echo "$FOLDER/$BASENAME" | tr -s /)
                        bashio::log.info "Sync delete with Dropbox..."
                        ./dropbox_uploader.sh -f $CONFIG_FILE delete "$FILE_PATH"
                    fi
                done
                bashio::log.info "Done with deletes"
            fi

            # find remaining files and upload to dropbox
            bashio::log.info "Uploading local files to Dropbox..."
            ./dropbox_uploader.sh -s -f $CONFIG_FILE upload $BACKUP_DIR/*.tar "$FOLDER"
            bashio::log.info "Done with uploads"
            bashio::log.info "Sync done"
            fi
    else
        # received unknown input
        bashio::log.notice "Ignoring unknown input: $INPUT"
    fi

    bashio::log.info "Listening for input via stdin service call..."
done
