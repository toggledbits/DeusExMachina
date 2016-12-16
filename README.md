DeusExMachina: The Vacation Plugin
=============

### Introduction ###

DeusExMachina is a plugin for the MiCasaVerde Vera home automation system. It takes over your house while you're away on vacation by creating a ghost that moves from room to room, turning on and off lights. Simply specify the lights you want to have controlled by the plugin, specify a "Lights Out" time when lights will begin to turn off, and come sundown DeusExMachina will take over.

There are currently two versions of Deus Ex Machina available:

* Deus Ex Machina -- version 1.1, for UI5; this is the legacy version and although it installs for UI6 and UI7, it does not work properly on those platforms.

* Deus Ex Machina II -- version 2.4, for UI7 (only). This version was developed and tested on firmware version 1.7.855, but should work for any full release of UI7 provided by MiCasaVerde.

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

UI7 introduced the concept of "House Modes." Version 2.3 and beyond of Deus Ex Machina have the ability to run only when the 
house is in one or more selected house modes. A set of checkboxes is used to selected which modes allow Deus Ex Machina to run. 
If no modes are chosen, it is the same as choosing all modes (Deus operates in any house mode).

Selecting the devices to be controlled is a simple matter of clicking the check boxes. Because the operating cycle of
the plug-in is random, any controlled device may be turned on and off several times during the cycling period (between sunset and Lights Out time).
As of version 2.4, lights on dimmers can be set to any level by setting the slider that appears to the right of the device name. Non-dimming devices are simply turned on and off. 

As of version 2.4, all devices are listed that implement the SwitchPower1 and Dimming1 services. This leads to some oddities,
like some motion sensors and thermostats being listed. It may not be entirely obvious (or standard) what a thermostat, for example, might do when you try to turn it off and on like a light, so be careful selecting these devices.

Also new for version 2.4 is the ability to run scenes during the random cycling period. Scenes must be specified in pairs, with
one being the "on" scene and the other being an "off" scene. This not only allows more patterned use of lights, but also gives the user
the ability to handle device-specific capabilities that would be difficult to implement in DEMII. For example, while DEMII can now
turn Philips Hue lights on and off (to dimming levels, even), it cannot control their color because there's no UI for that in
DEMII. But a scene could be used to control that light or a group of lights, with their color.

Version 2.4 also adds the ability to limit the number of targets (devices or scenes) that DEMII can have "on" simultaneously. If this limit is 0, there is no limit enforced.

Finally, 2.4 adds the ability for a "final scene" to run when DEMII is disabled or turns off the last light after the "lights out" time. This could be used for any purpose. I personally use it to make sure a whole-house off is run, but you could use it to ensure your alarm system is armed, or your garage door is closed, etc.

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

Note that when disabling Deus Ex Machina from a scene or the user interface, versions 1.1 and 2.0 operate differently. Version 1.1 will simply stop cycling lights, leaving on any controlled lights it may have turned on. 
Version 2, however, will turn off all controlled lights _if it was in the cycling period (between sunset and lights out time) at the time it was disabled_.

Version 2.0 also added the ability for a change of DeusExMachina's Enabled state to be used as trigger in scenes and other places where events can be watched (e.g. Program Logic plugins, etc.). This also works on UI7 only.

#### Triggers ####

Version 2.0 on UI7 supports events (e.g. to trigger a scene or use with Program Logic Event Generator) for its state changes.

If the "device is enabled or disabled" event is chosen, the trigger will fire when DEMII's state is changed to enabled or disabled (you will be given the option to choose which).

For the "operating mode changes" event, the trigger fires when DEMII's operating mode changes. DEMII's operating modes are:

* Standby - DEMII is disabled (this is equivalent to the "device is disabled" state event);

* Ready - DEMII is enabled and waiting for the next sunset;

* Cycling - DEMII is enabled and cycling lights in the active period after sunset and before the "lights out" time;

* Shut-off - DEMII is enabled and shutting off lights, having reached the "lights out" time.

When disabled, DEMII is always in Standby mode. When enabled, DEMII enters the Ready mode, then transitions to Cycling mode at sunset, then Shut-off mode at the "lights out" time, and then when all lights have
been shut off, returns to the Ready mode waiting for the next day's sunset. The transition between Ready, Cycling, and Shut-off continues until DEMII is disabled (at which point it goes to Standby).

It should be noted that DEMII can enter Cycling or Shut-off mode immediately, without passing through Ready, if it is enabled after sunset or after the "lights out" time, respectively. 
DEMII will also transition into or out of Standby mode immediately and from any other mode when disabled or enabled, respectively.

#### Cycle Timing ####

Version 2.0 has added device state variables to alter the default cycle timing. They can be changed by accessing them through the "Advanced" tab in the device user interface.
The random delay between turning lights on or off is between 5 and 30 minutes by default. By setting `MinCycleTime` and `MaxCycleTime` (integer number of seconds,
default 300 and 1800, respectively), the user can modify the default settings for on/off cycling. Similarly the `MinOffTime` and `MaxOffTime` variables (default 60 and 300 seconds,
respectively) change the rate of the "lights out" mode (i.e. the transition to all lights out at the user-configured time).
