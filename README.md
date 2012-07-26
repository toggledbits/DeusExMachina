DeusExMachina: The Vacation Plugin
=============

### Introduction ###

DeusExMachina is a plugin for the MiCasaVerde Vera home automation system. It takes over your house while you're away on vacation by creating a ghost that moves from room to room, turning on and off lights. Simply specify the lights you want to have controlled by the plugin, specify a "Lights Out" time when lights will begin to turn off, and come sundown DeusExMachina will take over.

### How It Works ###

Once DeusExMachina is activated, or the following Sundown occurs, it picks a random light from its configured list of lights, and switches its state. DeusExMachina continues doing this at random intervals between 5 and 30 minutes until the Lights Off time or Sunrise. When that happens, the same pattern is followed, however a random light in an _On_ state is chosen to turn Off. Once all lights are off, DeusExMachina goes to sleep until the next Sundown.