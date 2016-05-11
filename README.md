DeusExMachina: The Vacation Plugin
=============

### Introduction ###

DeusExMachina is a plugin for the MiCasaVerde Vera home automation system. It takes over your house while you're away on vacation by creating a ghost that moves from room to room, turning on and off lights. Simply specify the lights you want to have controlled by the plugin, specify a "Lights Out" time when lights will begin to turn off, and come sundown DeusExMachina will take over.

### History ###

DeusExMachina was originally written and published in 2012 by Andy Lintner (beowulfe), and maintained by Andy through the 1.x versions. In May 2016, Andy turned the project over to Patrick Rigney (toggledbits here on Github, rigpapa in the MCV/Mios world) for ongoing support (version 2.0 onward).

For information about modifications, fixes and enhancements, please see the Changelog.

### How It Works ###

When DeusExMachina is activated, it first waits until sunset. It then begins to toggle lights on the list of controlled devices (which is user-configured), with a random delay of between 5 and 30 minutes between each device. Then, when a user-configured "lights out" time is reached, the plug-in begins to turn randomly turn off any of the controlled lights that are on, until all are off. It then waits until the next day to resume its work at sunset, if it is still enabled.

In the "lights out" mode, DeusExMachina prior to version 2.0 used the same 5-30 minute range of delays to turn off each light. If a large number of lights was configured, it could potentially take hours past the user-specified "lights out" time to turn them all off. As of version 2.0, the default range is between 1 and 5 minutes. This can be changed as further described below.

For more information, see Additional Documentation below.

### Reporting Bugs/Enhancement Requests ###

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

### License ###

DeusExMachina is offered under GPL (the GNU Public License).

### Additional Documentation ###

#### Control by Scene ####

As of version 2.0 and on UI7, DeusExMachina can be enabled or disabled like a light switch in scenes, through the regular graphical interface (no Lua required).

A Lua interface is also supported since version 1.1 for both UI5 and UI7, via a luup.call_action() call:

```
luup.call_action("urn:toggledbits-com:serviceId:DeusExMachinaII1", "SetEnabled", { NewEnabledValue = "0|1" }, deviceID)
```

Of course, only one of either "0" or "1" should be specified.

Version 2.0 also added the ability for a change of DeusExMachina's Enabled state to be used as trigger in scenes and other places where events can be watched (e.g. Program Logic plugins, etc.). This also works on UI7 only.

#### Cycle Timing ####

Version 2.0 has added hidden device variables to alter the default cycle timing. The random delay between turning lights on or off is between 5 and 30 minutes by default. By setting `MinCycleTime` and `MaxCycleTime` (integer number of seconds, default 300 and 1800, respectively), the user can modify the default settings for on/off cycling. Similarly the `MinOffTime` and `MaxOffTime` variables (default 60 and 300 seconds, respectively) change the rate of the "lights out" mode (i.e. the transition to all lights out at the user-configured time).

