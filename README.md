DeusExMachina: The Vacation Plugin
=============

### Introduction ###

DeusExMachina is a plugin for the MiCasaVerde Vera home automation system. It takes over your house while you're away on vacation by creating a ghost that moves from room to room, turning on and off lights. Simply specify the lights you want to have controlled by the plugin, specify a "Lights Out" time when lights will begin to turn off, and come sundown DeusExMachina will take over.

There are currently two versions of Deus Ex Machina available:

* Deus Ex Machina -- version 1.1, for UI5; this is the legacy version and although it installs for UI6 and UI7, it does not work properly on those platforms.

* Deus Ex Machina II -- version 2.0, for UI7; this is the new plugin. It is for all versions of firmware, but has only been tested under UI7. Testing and bug reports for UI5 and UI6 would be appreciated.

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

#### Installation ####

The plugin is installed in the usual way: 

* On UI7, go to Apps in the left navigation, and click on "Install Apps". Search for "Deus Ex Machina II" (make sure you include the "II" at the end to get the UI7-compatible version), and then click the
"Details" button in its listing of the search results. From here, simply click "Install" and wait for the install to complete. A full refresh of the UI is necessary (e.g. Ctrl-F5 on Windows) after installation.

* On UI5, click on APPS in the top navigation bar, then click "Install Apps". Search for "Deus Ex Machina". The search results will show "Deus Ex Machina" and "Deus Ex Machina II". At this time, it is recommended
that you install the legacy version only on UI5 (unless you want to help me test the new version), which is "Deus Ex Machina". Click on the "Details" button, and then click "Install". Once the install completes,
one or more full refreshes of the browser (e.g. Ctrl-F5 on Windows) will be necessary.

Once you have installed the plugin and refreshed the browser, you can proceed to device configuation.

#### Simple Configuration ####

Deus Ex Machina's "Configure" tab allows you to set up the set of lights that should be controlled, and the time at which DEM should begin shutting lights off to simulate the house occupants going to sleep.

The "Lights Out" time is a time, expressed in 24-hour HH:MM format, that is the time at which lights should begin shutting off. This time should be after sunset. Keep in mind that sunset is a moving target, and
at certain times of year in some places can be quite late, so a Lights Out time of 20:15, for example, may be too early. The lights out time can be a time after midnight.

Selecting the lights to be controlled is a simple matter of clicking the check boxes. Lights on dimmers cannot be set to values less than 100% in the current version of the plugin. Because the operating cycle of
the plug-in is random, any controlled light may be turned on and off several times during the cycling period (between sunset and Lights Out time).

#### Control by Scene ####

As of version 2.0 and on UI7, DeusExMachina can be enabled or disabled like a light switch in scenes, through the regular graphical interface (no Lua required).

A Lua interface is also supported since version 1.1 for both UI5 and UI7, via a luup.call_action() call:

```
-- For the new Deus Ex Machina II plugin (v2.0 and higher), do this:
luup.call_action("urn:toggledbits-com:serviceId:DeusExMachinaII1", "SetEnabled", { NewEnabledValue = "0|1" }, deviceID)

-- For the old Deus Ex Machina plugin (v1.1 and earlier) running on UI5 or UI7, do this:
luup.call_action("urn:futzle-com:serviceId:DeusExMachina1", "SetEnabled", { NewEnabledValue = "0|1" }, deviceID)
```

Of course, only one of either "0" or "1" should be specified.

Note that When disabling Deus Ex Machina from a scene, versions 1.1 and 2.0 operate differently. Version 1.1 will simply stop cycling lights, leaving on any controlled lights it may have turned on. Version 2, however, 
will turn off all controlled lights _if it was in the cycling period (between sunset and lights out time) at the time it was disabled_.

Version 2.0 also added the ability for a change of DeusExMachina's Enabled state to be used as trigger in scenes and other places where events can be watched (e.g. Program Logic plugins, etc.). This also works on UI7 only.

#### Cycle Timing ####

Version 2.0 has added device state variables to alter the default cycle timing. They can be changed by accessing them through the "Advanced" tab in the device user interface. The random delay between turning lights on or off is between 5 and 30 minutes by default. By setting `MinCycleTime` and `MaxCycleTime` (integer number of seconds, default 300 and 1800, respectively), the user can modify the default settings for on/off cycling. Similarly the `MinOffTime` and `MaxOffTime` variables (default 60 and 300 seconds, respectively) change the rate of the "lights out" mode (i.e. the transition to all lights out at the user-configured time).

