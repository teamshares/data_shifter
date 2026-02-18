# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Loud warning and 5-second countdown when running with `transaction false` / `:none`, reminding that dry run only applies if writes are guarded with `dry_run?`. Use `DATA_SHIFTER_NO_TX_COUNTDOWN=0` to skip the countdown in CI/scripts.

## [0.1.0] - Initial release
