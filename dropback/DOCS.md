# Dropback

Sync Home Assistant backups to Dropbox.

This Add-on will sync all `/backup/*.tar` files to Dropbox and optionally delete backups older than a set number of days both from the local backup directory and optionally from Dropbox.

### About

This Add-on allows you to upload your Home Assistant backups to your Dropbox, keeping your backups safe and available in case of hardware failure. Uploads are triggered via a service call, making it easy to automate periodic backups or trigger uploads to Dropbox on demand.

The inspiration for this Add-on came from https://github.com/danielwelch/hassio-dropbox-sync/ which appears to no longer be maintained.

You will need to create a Dropbox App and generate an Access Token for this Add-on to work.

### Installation

1. Add the Add-on repository to your Home Assistant instance: `https://github.com/matthewhadley/homeassistant-dropback`
2. Install the Dropback Add-on
3. Configure the Add-on following the steps below

### Configuration

Dropback uploads all backup files (specifically, all `.tar` files) in the `/backup` directory to a specified folder in your Dropbox. This target folder is specified via the `Folder` configuration option. If `Folder` is left blank, or set to `/`, the root folder the App has access to is used. Using a Scoped Access App is highly recommended, where the App is restricted to its App folder only.

If set to a non zero value, Dropback will `Delete backups older than this many days`. Set to `0` to never Delete backups. You can also sync the deletion of backups to Dropbox by setting the `Sync Deletes` flag. This will mean that Dropbox will also only keep backups up to the set number of days.

To access your personal Dropobox, this Add-on requires you create an App and generate an Access Token. Follow these steps to create an App and Access Token:

1. Go to https://www.dropbox.com/developers/apps
2. Click the "Create App" button
3. Select "Scoped Access" and "App folder". This restrcts the App to a single folder of your dropbox.
4. Give your App a unique name and click "Create"
5. Select the "Permissions" tab, enable "files.content.write" and click "Submit"
6. On the "Settings" tab find the `App key` and `App secret` values and add them into this Add-on's configuration
7. Visit the url https://www.dropbox.com/oauth2/authorize?client_id=YOUR_APP_KEY_HERE&token_access_type=offline&response_type=code to get your one-use Access Code. Remember to replace the YOUR_APP_KEY_HERE value with the one above. Add the Access Code into this Add-on's configuration
8. You can now start the Add-on

The one-use Access Code typically expires in ~4hrs and is used on the first run of the Add-on to get a long lived Refresh Token. The Refresh Token will allow the Add-on to request short lived Dropbox access tokens as needed.

### Usage

Once the Add-on is started, it is listening for service calls. You can trigger a sync operation by calling the `hassio.addon_stdin` service with the following YAML:

```yaml
service: hassio.addon_stdin
data:
  addon: 719b45ef_dropback
  input: sync
```
