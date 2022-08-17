#!/usr/bin/with-contenv bashio

CONFIG_PATH=/data/options.json
OAUTH_APP_KEY="$(bashio::config 'oauth_app_key')"
OAUTH_APP_SECRET="$(bashio::config 'oauth_app_secret')"
OAUTH_ACCESS_CODE="$(bashio::config 'oauth_access_code')"
FOLDER="$(bashio::config 'folder')"
DELETE_OLDER_THAN="$(bashio::config 'delete_older_than')"
SYNC_DELETES="$(bashio::config 'sync_deletes')"

FOLDER=$(echo "$FOLDER" | tr -s /)
BACKUP_DIR="/backup"
CONFIG_FILE="/uploader.conf"
REFRESH_TOKEN_FILE="/config/719b45ef_dropback.conf"

log() {
    date +"%Y-%m-%d %T $*"
}

log "Initializing Dropback"

if [ ! -e "$REFRESH_TOKEN_FILE" ]; then
    log "No stored Refresh Token found at $REFRESH_TOKEN_FILE"
    log "Requesting long lived Refresh Token..."
    OAUTH_REFRESH_TOKEN=$(curl https://api.dropbox.com/oauth2/token \
    -d grant_type=authorization_code \
    -u $OAUTH_APP_KEY:$OAUTH_APP_SECRET \
    -d code=$OAUTH_ACCESS_CODE \
    --silent | jq -r .refresh_token)

    log "Storing encrypted Refresh Token at $REFRESH_TOKEN_FILE"
    echo $OAUTH_REFRESH_TOKEN | openssl aes-256-cbc -a -salt -pass pass:$OAUTH_APP_SECRET 2> /dev/null 1> $REFRESH_TOKEN_FILE
fi

if [ ! -e "$CONFIG_FILE" ]; then
    log "Using encrypted Refresh Token at $REFRESH_TOKEN_FILE"
    OAUTH_REFRESH_TOKEN=$(cat $REFRESH_TOKEN_FILE | openssl aes-256-cbc -d -a -salt -pass pass:$OAUTH_APP_SECRET 2> /dev/null)

    echo "CONFIGFILE_VERSION=2.0" > "$CONFIG_FILE"
    echo "OAUTH_APP_KEY=$OAUTH_APP_KEY" >> "$CONFIG_FILE"
    echo "OAUTH_APP_SECRET=$OAUTH_APP_SECRET" >> "$CONFIG_FILE"
    echo "OAUTH_REFRESH_TOKEN=$OAUTH_REFRESH_TOKEN" >> "$CONFIG_FILE"
fi

log "Validating Dropbox access... "
./dropbox_uploader.sh -q -f $CONFIG_FILE space > /dev/null
if [ $? -eq 0 ]; then
   log "Dropbox access OK"
else
   log "ERROR validating Dropbox access. Please check configuration and restart."
   exit 1
fi

log "Listening for input via stdin service call..."

# listen for input
while read -r INPUT; do
    INPUT=${INPUT:1:-1}
    log "Received input: $INPUT"
    if [[ "$INPUT" = "sync" ]]; then

        # find files older than X days, delete locally and delete on dropbox
        if [[ $DELETE_OLDER_THAN != "0" ]]; then
            log "Deleting files older than $DELETE_OLDER_THAN day(s)"
            find /backup -maxdepth 1 -mtime +$(($DELETE_OLDER_THAN-1)) -type f -name "*.tar" -print0 |
            while IFS= read -r -d '' FILE; do
                rm $FILE
                log "Deleted local file $FILE"
                if [[ $SYNC_DELETES = "true" ]]; then
                    BASENAME=$(basename $FILE)
                    FILE_PATH=$(echo "$FOLDER/$BASENAME" | tr -s /)
                    log "Sync delete with Dropbox..."
                    ./dropbox_uploader.sh -f $CONFIG_FILE delete "$FILE_PATH"
                fi
            done
            log "Done with deletes"
        fi

        # find remaining files and upload to dropbox
        log "Uploading local files to Dropbox..."
        ./dropbox_uploader.sh -s -f $CONFIG_FILE upload /backup/*.tar "$FOLDER"
        log "Done with uploads"
        log "Sync done"

    else
        # received undefined command
        log "Ignoring unknown input: $INPUT"
    fi

    log "Listening for input via stdin service call..."
done
