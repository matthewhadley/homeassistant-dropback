## [5.0.0] - 2022-09-10

### BREAKING

- Don’t exit process on failure to delete or upload, but log fatal error instead

### Added

- Add check for network connectivity

### Changed

- Output Dropback version in logs
- Make log messaging more consistent

## [4.0.0] - 2022-08-28

### Added

- Check for incorrect App permissions
- Capture and output errors from dropbox_uploader.sh script

## [3.1.0] - 2022-08-25

### Fixed

- Check for empty backup names

## [3.0.0] - 2022-08-25

### Added

- Support use of backup names or filenames when syncing to Dropbox

### Changed

- Logging output format

## [2.4.0] - 2022-08-21

### Changed

- add date to default bashio log timestamp

## [2.3.1] - 2022-08-19

### Changed

- update error message for failed Dropbox access validation

## [2.3.0] - 2022-08-18

### Changed

- no longer mount config dir

## [2.2.1] - 2022-08-18

### Changed

- update documentation for configuration

## [2.2.0] - 2022-08-18

### Changed

- use bashio logging and script exit functions

## [2.1.1] - 2022-08-18

### Changed

- bump version to debug container rebuild

## [2.1.0] - 2022-08-18

### Added

- Error checking and messaging for first set-up

## [2.0.0] - 2022-08-18

### Changed

- Use available persistent storage at `/data` for conf file

## [1.1.1] - 2022-08-18

### Added

- Homepage url in config

## [1.1.0] - 2022-08-17

### Added

- Add timestamps to log output

## [1.0.0] - 2022-08-16

### Added

- First release, with functionality to upload backups to Dropbox and optionally delete backups older than user configured days
