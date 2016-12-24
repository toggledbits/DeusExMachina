DeusExMachina: The Vacation Plugin
=============

### Introduction ###

DeusExMachina is a plugin for the MiCasaVerde Vera home automation system. It takes over your house while you're away on vacation by creating a ghost that moves from room to room, turning on and off lights. Simply specify the lights you want to have controlled by the plugin, specify a "Lights Out" time when lights will begin to turn off, and come sundown DeusExMachina will take over.

There are currently two versions of Deus Ex Machina available:

* Deus Ex Machina -- for UI5 (only); this is the legacy version and although it installs for UI6 and UI7, it does not work properly on those platforms. This version is only available from the MiCasaVerde plugin library.

* Deus Ex Machina II -- for UI7 (only). This version was developed and tested on firmware version 1.7.855, but should work for any full release of UI7 provided by MiCasaVerde. The current release is available via both GitHub and the MiCasaVerde plugin library. Advanced builds are also available in the GitHub repository.

### History ###

DeusExMachina was originally written and published in 2012 by Andy Lintner (beowulfe), and maintained by Andy through the 1.x versions. In May 2016, Andy turned the project over to Patrick Rigney (toggledbits here on Github, rigpapa in the MCV/MiOS world) for ongoing support (version 2.0 onward). At this point, the plugin became known as Deus Ex Machina II, or just DEMII.

### How It Works ###

When Deus Ex Machina II (DEMII) is enabled, it first waits until two conditions are satisfied: the current time is at or after sunset, and the "house mode" is one of the selected modes in which DEMII is configured by the user to be active. If both conditions are met, DEMII enters a cycle of turning a set of user-selected lights on and off at random intervals. This continues until the user-configured "lights out" time, at which point DEMII begins its shutdown cycle, in which any of the user-selected lights that are on are turned off at random intervals until all lights are off. DEMII then waits until the next day's sunset.

For more information, see Additional Documentation below.

### Reporting Bugs/Enhancement Requests ###

Bug reports and enhancement requests are welcome! Please use the "Issues" link for the repository to open a new bug report or make an enhancement request.

### License ###

DeusExMachina is offered under GPL (the GNU Public License).

### Additional Documentation ###

#### Installation ####

The plugin is installed in the usual way: go to Apps in the left navigation, and click on "Install Apps". 
Search for "Deus Ex Machina II" (make sure you include the "II" at the end to get the UI7-compatible version), 
and then click the "Details" button in its listing of the search results. From here, simply click "Install" 
and wait for the install to complete. A full refresh of the UI is necessary (e.g. Ctrl-F5 on Windows) after installation.

Once you have installed the plugin and refreshed the browser, you can proceed to device configuation.

#### Simple Configuration ####

Deus Ex Machina's "Configure" tab gives you a set of simple controls to control the behavior of your vacation haunt.

##### Lights-Out Time #####

The "Lights Out" time is a time, expressed in 24-hour HH:MM format, that is the time at which lights should begin 
shutting off. This time should be after sunset. Keep in mind that sunset is a moving target, and
at certain times of year in some places can be quite late, so a Lights Out time of 20:15, for example, may not be 
a good choice for the longest days of summer. The lights out time can be a time after midnight.

##### House Modes #####

The next group of controls is the House Modes in which DEMII should be active when enabled. If no house mode is selected,
DEMII will operate in _any_ house mode.

##### Controlled Devices #####

Next is a set of checkboxes for each of the devices you'd like DEMII to control.
Selecting the devices to be controlled is a simple matter of clicking the check boxes. Because the operating cycle of
the plug-in is random, any controlled device may be turned on and off several times during the cycling period (between sunset and Lights Out time).
Dimming devices can be set to any level by setting the slider that appears to the right of the device name. 
Non-dimming devices are simply turned on and off (no dimmer slider is shown for these devices).

> Note: all devices are listed that implement the SwitchPower1 and Dimming1 services. This leads to some oddities,
> like some motion sensors and thermostats being listed. It may not be entirely obvious (or standard) what a thermostat, for example, 
> might do when you try to turn it off and on like a light, so be careful selecting these devices.

##### Scene Control #####

The next group of settings allows you to use scenes with DEMII. 
Scenes must be specified in pairs, with
one being the "on" scene and the other being an "off" scene. This not only allows more patterned use of lights, but also gives the user
the ability to handle device-specific capabilities that would be difficult to implement in DEMII. For example, while DEMII can
turn Philips Hue lights on and off (to dimming levels, even), it cannot control their color because there's no UI for that in
DEMII. But a scene could be used to control that light or a group of lights, with their color, as an alternative to direct control by DEMII.

Both scenes and individual devices (from the device list above) can be used simultaneously.

##### Maximum "On" Targets #####

Version 2.4 also adds the ability to limit the number of targets (devices or scenes) that DEMII can have "on" simultaneously. 
If this limit is 0, there is no limit enforced. If you have DEMII control a large number of devices, it's probably not a bad idea to 
set this value to some reasonable limit.

##### Final Scene #####

DEMII allows a "final scene" to run when DEMII is disabled or turns off the last light after the "lights out" time. This could be used for any purpose. I personally use it to make sure a whole-house off is run, but you could use it to ensure your alarm system is armed, or your garage door is closed, etc.

#### Control of DEMII by Scenes ####

DeusExMachina can be enabled or disabled like a light switch in scenes, through the regular graphical interface (no Lua required).
A Lua interface is also supported. All versions of support the SetEnabled action, although for DEMII versions 2.4 and higher, the use of SetTarget in the standard SwitchPower1 service is preferred. Examples (the "0|1" means use either 0 or 1 to disable or enable, respectively):

```
-- Preferred for DEMII versions 2.4 and higher:
luup.call_action("urn:upnp-org-serviceId:SwitchPower1", "SetTarget", { newTargetValue = "0|1" }, deviceID)

-- Also works for all versions of DEMII:
luup.call_action("urn:toggledbits-com:serviceId:DeusExMachinaII1", "SetEnabled", { NewEnabledValue = "0|1" }, deviceID)

-- For the old Deus Ex Machina plugin (v1.1 and earlier) running on UI5 or UI7, do this:
luup.call_action("urn:futzle-com:serviceId:DeusExMachina1", "SetEnabled", { NewEnabledValue = "0|1" }, deviceID)
```

#### Triggers ####

DEMII signals changes to its enabled/disabled state, and changes to its internal operating mode. These can be used as triggers for scenes or notifications. DEMII's operating modes are:

* Standby - DEMII is disabled (this is equivalent to the "device is disabled" state event);

* Ready - DEMII is enabled and waiting for the next sunset (and house mode, if applicable);

* Cycling - DEMII is cycling lights, that is, it is enabled, in the period between sunset and the set "lights out" time, and correct house mode (if applicable);

* Shut-off - DEMII is enabled and shutting off lights, having reached the "lights out" time.

When disabled, DEMII is always in Standby mode. When enabled, DEMII enters the Ready mode, then transitions to Cycling mode at sunset, then Shut-off mode at the "lights out" time,
and then when all lights have been shut off, returns to the Ready mode waiting for the next day's sunset. The transition between Ready, Cycling, and Shut-off continues until DEMII 
is disabled (at which point it goes to Standby).

It should be noted that DEMII can enter Cycling or Shut-off mode immediately, without passing through Ready, if it is enabled after sunset or after the "lights out" time, 
respectively. DEMII will also transition into or out of Standby mode immediately and from any other mode when disabled or enabled, respectively.

#### Cycle Timing ####

DEMII's cycle timing is controlled by a set of state variables. By default, DEMII's random cycling of lights occurs at randomly selected intervals between 300 seconds (5 minutes) and 1800 seconds (30 minutes), as determined by the `MinCycleDelay` and `MaxCycleDelay` variables. You may change these values to customize the cycling time for your application.

When DEMII is in its "lights out" (shut-off) mode, it uses a different set of shorter (by default) cycle times, to more closely imitate actual human behavior. The random interval for lights-out is between 60 seconds and 300 seconds (5 minutes), as determined by `MinOffDelay` and `MaxOffDelay`. These intervals could be kept short, particularly if DEMII is controlling a large number of lights.

#### Troubleshooting ####

If DEMII isn't behaving as expected, post a message in the MCV forums 
[in this thread](http://forum.micasaverde.com/index.php/topic,11333.0.html)
or open up an issue in the 
[GitHub repository](https://github.com/toggledbits/DeusExMachina/issues).

Please don't just say "DEMII isn't working for me." I can't tell you how long a piece of string is without seeing the piece of string. Give me details of what you are doing, how you are configured, and what behavior you observe.

##### Test Mode and Log Output #####

If I'm troubleshooting a problem with you, I may ask you to enable test mode, run DEMII a bit, and send me the log output. Here's how you do that:

1. Go into the setting for the DEMII device, and click the "Advanced" tab.
1. Click on the Variables tab.
1. Set the TestMode variable to 1 (just change the field and hit the TAB key)
1. If requested, set the TestSunset value to whatever I ask you (this allows the sunset time to be overriden so we don't have to wait for real sunset to see what DEMII is doing).

### FAQ ###

<dl>
    <dt>What happens if DEMII is enabled afer sunset? Does it wait until the next day to start running?</dt>
    <dd>No. If DEMII is enabled during its active period (between sunset and the configured "lights out" time,
        it will begin cycling the configured devices and scenes.</dd>

    <dt>What's the difference between House Mode and Enabled/Disabled? Can I just use House Mode to enable and disable DEMII?</dt>
    <dd>The enabled/disabled state of DEMII is the "big red button" for its operation. If you configure DEMII to only run in certain
        house modes, then you can theoretically leave DEMII enabled all the time, as it will operate (cycle lights) only when a
        selected house mode is active. But, some people don't use the House Modes for various reasons, so having a master switch
        for DEMII is necessary.</dd>
     
    <dt>I have a feature request. Will you implement it?</dt>
    <dd>Absolutely definitely maybe. I'm willing to listen to what you want to do. But, keep in mind, nobody's getting rich writing Vera
        plugins, and I do other things that put food on my table. And, what seems like a good idea to you may be just that: a good idea for 
        the way _you_ want to use it. The more generally applicable your request is, the higher the likelihood that I'll entertain it. What
        I don't want to do is over-complicate this plug-in so it begins to rival PLEG for size and weight (no disrespect intended there at
        all--I'm a huge PLEG fan and use it extensively, but, dang). DEMII really has a simple job: make lights go on and off to cast a serious
        shadow of doubt in the mind of some knucklehead who might be thinking your house is empty and ripe for his picking. In any case,
        the best way to give me feature requests is to open up an issue (if you have a list, one issue per feature, please) in the
        [GitHub repository](https://github.com/toggledbits/DeusExMachina/issues). Second best is sending me a message via the MCV forums 
        (I'm user `rigpapa`).
        </dd>
</dl>        
