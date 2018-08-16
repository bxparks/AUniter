# Changelog

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
