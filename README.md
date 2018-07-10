# AUniter Command Line Tools and Continuous Integration for Arduino

Tools for implementing continuous integration (CI) for Arduino
microcontroller boards, and validating unit tests written in
[AUnit](https://github.com/bxparks/AUnit).
The tools can be integrated with a locally hosted [Jenkins](https://jenkins.io)
continuous integration system.

There are 3 components to the **AUniter** package:

1. Command line tools (`tools/`) that can compile and upload Arduino programs
   to microcontroller boards programmatically.
1. Integration with a locally hosted Jenkins system (`jenkins/`).
1. A badge service (`BadgeService/`) running on Google Functions that allows the
   locally hosted Jenkins system to update the status of the build, so that an
   indicator badge can be displayed on a source control repository like GitHub.

Version: 1.2 (2018-06-29)

## Installation

1. See [AUniter tools](tools/README.md) to install the command line tools.
1. See [AUniter Jenkins Integration](jenkins/README.md) to integrate with
   Jenkins.
1. See [AUniter Badge Service](BadgeService/README.md) to display the
   build status in the source repository.

## System Requirements

* AUniter Tools requires the following:
    * Arduino IDE 1.8.5
    * I have tested the integration on the following systems:
        * Ubuntu 16.04, 17.10, 18.04
        * Xubuntu 18.04
* AUniter Integration with Jenkins requires the following:
    * AUniter Tools
    * AUnit (optional)
    * Jenkins Continuous Integration platform
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
  due to Issue #4.

## License

[MIT License](https://opensource.org/licenses/MIT)

## Authors

* Created by Brian T. Park (brian@xparks.net).
