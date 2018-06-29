# Changelog

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
