# AUniter Command Line Tools and Continuous Integration for Arduino

Tools for implementing continuous integration (CI) for Arduino
microcontroller boards, and validating unit tests written in
[AUnit](https://github.com/bxparks/AUnit).
The tools can be integrated with a locally hosted [Jenkins](https://jenkins.io)
continuous integration system.

There are 3 components to the **AUniter** package:

1. Command line tools (`tools/`) that can compile and upload Arduino programs
   to microcontroller boards programmatically. Here are some examples supported
   by the `auniter.sh` command line tool:
1. Integration with a locally hosted Jenkins system (`jenkins/`).
1. A badge service (`BadgeService/`) running on
   [Google Cloud Functions](https://cloud.google.com/functions/)
   that allows the locally hosted Jenkins system to update the status of the
   build, so that an indicator badge can be displayed on a source control
   repository like GitHub.

The `auniter.sh` script uses the Arduino IDE binary in command line mode.
Here are some examples that you can perform on the command line:

* `$ auniter ports` - list the ports and devices
* `$ auniter verify nano Blink.ino` - verify `Blink.ino`
* `$ auniter verify nano,esp8266,esp32 Blink.ino` - verify on 3 target
  environments (`nano`, `esp8266`, `esp32`)
* `$ auniter upload nano:USB0 Blink.ino` - upload to the `nano` target
  connected to `/dev/ttyUSB0`
* `$ auniter test nano:USB0 BlinkTest.ino` - compile, upload, then validate
  the `BlinkTest.ino` unit test written using
  [AUnit](https://github.com/bxparks/AUnit)
* `$ auniter test nano:USB0,esp8266:USB1,esp32:USB2 BlinkTest/ ClockTest/`
  - upload and verify 2 sketches (`BlinkTest/BlinkTest.ino`,
  `ClockTest/ClockTest.ino`) on 3 target environments (`nano`, `esp8266`,
  `esp32`) located at the 3 respective ports (`/dev/ttyUSB0`, `/dev/ttyUSB1`,
  `/dev/ttyUSB2`)
* `$ auniter upmon nano:USB0 Blink.ino` - upload the sketch and monitor the
  serial port using a user-configurable terminal program (e.g. `picocom`) on
  `/dev/ttyUSB0`

Version: 1.7 (2018-09-16)

## Installation

1. See [AUniter tools](tools/) to install the command line tools.
1. See [AUniter Jenkins Integration](jenkins/) to integrate with
   Jenkins.
1. See [AUniter Badge Service](BadgeService/) to display the
   build status in the source repository.

## System Requirements

* AUniter Tools requires the following:
    * Arduino IDE 1.8.5, 1.8.6
    * I have tested the integration on the following systems:
        * Ubuntu 16.04, 17.10, 18.04
        * Xubuntu 18.04
* AUniter Integration with Jenkins requires the following:
    * AUniter Tools
    * [AUnit](https://github.com/bxparks/AUnit) (optional)
    * [Jenkins](https://jenkins.io) Continuous Integration platform
    * I have tested the integration on the following systems:
        * Ubuntu 16.04, 17.10, 18.04
        * Xubuntu 18.04
* AUniter BadgeService requires the following:
    * AUniter Integration with Jenkins
    * Google Functions

Some limited testing on MacOS has been done, but it is currently not supported.

Windows is definitely not supported because the scripts require the `bash`
shell. I am not familiar with
[Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
so I do not know if it would work on that.

## Limitations

* [Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not supported
  due to [Issue #4](https://github.com/bxparks/AUniter/issues/4).

## License

[MIT License](https://opensource.org/licenses/MIT)

## Feedback and Support

If you have any questions, comments, bug reports, or feature requests, please
file a GitHub ticket or send me an email. I'd love to hear about how this
software and its documentation can be improved. Instead of forking the
repository to modify or add a feature for your own projects, let me have a
chance to incorporate the change into the main repository so that your external
dependencies are simpler and so that others can benefit. I can't promise that I
will incorporate everything, but I will give your ideas serious consideration.

## Authors

* Created by Brian T. Park (brian@xparks.net).
