# Changelog

* Unreleased
* 1.7.2 (2020-08-21)
    * Look for a `*.ino` file in the current directory if no sketch file is
      specified for auniter.sh.
    * Add --preserve flag to auniter.sh to preserve compiler files, to allow
      dissembly by avr-objdump.
* 1.7.1 (2018-10-17)
    * Add SparkFun boards.
    * Fix incorrect handling of run-arduino.sh errors, now stops after an error.
    * Update instructions for installing 3rd party boards into the IDE used
      by Jenkins.
    * Write better summary section of README.md.
* 1.7 (2018-09-16)
    * Remove --board, --boards, and --ports flags to simplify the auniter.sh
      script.
    * Change name of `auniter.conf` to `auniter.ini` because tools (e.g. vim)
      are able to recoginize INI file format and handle them better
      (e.g. syntax highlighting).
    * Change the compile target from "board aliases" to "environments", where
      the "environment" is defined by a section of auniter.ini file whose name
      has the form `[env:NAME]`.
    * Add `port_timeout` parameters to the `[auniter]` section.
    * Add `locking` and 'board' parameters to the `[env:NAME]` section.
    * Add support for 'preprocessor' parameter in '[env:NAME]' section
      which defines a space-separated list of C-preprocessor macros in the
      form of `MACRO MACRO=value MACRO="string value"`.
    * Remove overly flexible --pref flag, replace with semantically specific
      flags (e.g. --sketchbook, --preprocessor).
    * Remove --monitor flag from `run_arduino.sh`. Was already replaced with
      shell exec to a user-definable terminal program. Add example
      configurations for 'picocom` and `microcom` terminal programs.
    * Add `auniter envs` subcommand which lists the environments defined in the
      auniter ini file.
    * Changed name of `--skip_if_no_port` flag to `--skip_missing_port`.
    * Add documentation of the recommended structure of `config.h` file to
      support multiple environments using both Arduino IDE and AUniter tools.
* 1.6 (2018-09-11)
    * Support 'monitor' subcommand using an external serial port terminal
      (e.g. picocom).
    * Add 'upmon' subcommand, a combination of 'upload' and 'monitor'.
    * Add '[auniter] baud' parameter to control default baud rate of port.
* 1.5 (2018-09-03)
    * Use subcommands instead of flags in auniter.sh to simplify the
      common interactive use cases.
* 1.4.1 (2018-09-03)
    * Fix bug which disabled --locking by default.
    * Allow serial port specifier in --boards flag to omit "/dev/tty" prefix.
* 1.4 (2018-08-16)
    * Reduce latency of BadgeService using statically cached images
      from shields.io.
    * Add proper cache-control directive in BadgeService to prevent GitHub
      from caching badges too aggressively.
    * Add --exclude option to allow some boards to skip some sketches which
      don't compile for those targets.
    * Add --nolocking option to avoid flock(1) for Leonardo/Mciro boards
      which use virtual serial ports. (Fixes #9)
    * Add new [options] section to the auniter.conf file format.
* 1.3 (2018-07-21)
    * Add BadgeService implemented using Google Functions to allow a locally
      hosted Jenkins to determine the shields.io that can be displayed in
      a GitHub README.md file.
    * Split the AUniter project into 3 parts: tools, jenkins, and
      BadgeService.
* 1.2 (2018-06-29)
    * Use a lock on the serial port (/dev/ttyXxx) to ensure that
      only one program uploads to a given Arduino board at the same time.
    * Update Jenkinsfile configuration to use system configuration for
      $AUNITER_ARDUINO_BINARY and parameterized build variable $BOARDS
      instead of $PORT.
    * Verify installation works on Ubuntu 16.04.
* 1.1.1 (2018-06-27)
    * Add `$PORT` parameter to the Jenkins web config to define the Arduino
      serial port instead of hardcoding it in the Jenkinsfile.
* 1.1 (2018-06-26)
    * Add instructions for setting up Jenkins continuous integration platform
      to use auniter.sh script.
    * Changed default config file from `~/.auniter_config` to `~/.auniter.conf`.
* 1.0 (2018-06-20)
    * Add auniter.sh commandline script that allows uploading and validation
      of multiple unit tests on multiple Arduino boards.
