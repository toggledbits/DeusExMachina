//# sourceURL=J_DeusExMachinaII1_UI7.js
/**
 * J_DeusExMachinaII1_UI7.js
 * Configuration interface for DeusExMachinaII
 *
 * Copyright 2016,2017 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DeusExMachinaII. For license information, see LICENSE at https://github.com/toggledbits/DeusExMachina
 */
/* globals api,jQuery,$,Utils */

//"use strict"; // fails on UI7, works fine with ALTUI

var DeusExMachinaII = (function(api, $) {

    // unique identifier for this plugin...
    var uuid = '11816AA9-0C7C-4E8F-B490-AAB429FA140F';

    var serviceId = "urn:toggledbits-com:serviceId:DeusExMachinaII1";

    var myModule = {};

    var controlled = [];
    var sceneNamesById = [];

    function onBeforeCpanelClose(args) {
        // console.log('handler for before cpanel close');
    }

    function init() {
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }

    function isDimmer(devid) {
        var v = api.getDeviceState( devid, "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus" );
        if (v === undefined || v === false) return false;
        return true;
    }

    function isControllable(devid) {
        var v = api.getDeviceState( devid, "urn:toggledbits-com:serviceId:DeusExMachinaII1", "LightsOut" );
        if (!(v === undefined || v === false)) return false; /* exclude self */
        if (isDimmer(devid)) return true; /* a dimmer is a light */
        v = api.getDeviceState( devid, "urn:upnp-org:serviceId:SwitchPower1", "Status" );
        if (v === undefined || v === false) return false;
        return true;
    }

    function getControlledList() {
        var deusDevice = api.getCpanelDeviceId();
        var list = api.getDeviceState(deusDevice, serviceId, "Devices"); // ???
        if ( !list || list.match(/^\s*$/)) {
            return [];
        }
        return list.split(',');
    }

    function updateControlledList()
    {
        controlled = [];
        jQuery('input.controlled-device:checked').each( function( ix, obj ) {
            var devid = jQuery(obj).attr('id').substr(6);
            var level = 100;
            var ds = jQuery('div#slider' + devid);
            var max = jQuery('input#ontime' + devid).val();
            if (ds.length == 1)
                level = ds.slider('option','value');
            if (level < 100)
                devid += '=' + level;
            if ( undefined !== max && parseInt(max) > 0)
                devid += '<' + parseInt(max);
            controlled.push(devid);
        });
        jQuery('.controlled-scenes').each( function( ix, obj ) {
            var devid = jQuery(obj).attr('id');
            // console.log('updateControlledList: handling scene pair ' + devid);
            controlled.push(devid);
        });

        var s = controlled.join(',');
        // console.log('Updating controlled list to ' + s);
        var deusDevice = api.getCpanelDeviceId();
        api.setDeviceStatePersistent(deusDevice, serviceId, "Devices", s, 0);
    }

    // Find a controlled device in the Devices list
    function findControlledDevice(deviceId)
    {
        for (var k=0; k<controlled.length; ++k) {
            if (controlled[k].charAt(0) != 'S') { // skip scene control
                // Handle dev=dimlevel syntax
                var l = controlled[k].indexOf('=');
                if (l < 0) l = controlled[k].indexOf('<');
                if (l < 0 && controlled[k] == deviceId.toString()) return k;
                if (controlled[k].substr(0,l) == deviceId.toString()) return k;
            }
        }
        return -1; // not found
    }

    function getControlled(ix)
    {
        if (ix < 0 || ix >= controlled.length) return undefined;
        var ret = {};
        var c = controlled[ix];
        var l;
        ret.index = ix;
        ret.raw = c;
        if (c.charAt(0) == 'S') {
            ret.type = "scene";
            l = c.indexOf('-');
            ret.onScene = c.substr(1,l-1); // portion after S and before -
            ret.offScene = c.substr(l+1); // after -
        } else {
            ret.type = "device";
            l = c.indexOf('=');
            var m = c.indexOf('<');
            var d,v;
            if (l < 0) {
                if (m > 0)
                    d = c.substr(0,m-1);
                else
                    d = c;
                v = 100;
            } else {
                d = c.substr(0,l);
                if (m > 0)
                    v = c.substr(l+1, m-(l+1));
                else
                    v = c.substr(l+1);
            }
            if (m > 0)
                ret.maxon = c.substr(m+1);
            else
                ret.maxon = null;
            ret.device = d;
            ret.value = v;
        }
        return ret;
    }

    function findControlledSceneSpec(sceneSpec)
    {
        return jQuery.inArray(sceneSpec, controlled);
    }

    function timeMinsToStr(totalMinutes)
    {
        var hours = Math.floor(totalMinutes / 60);
        if (hours < 10) {
            hours = "0"+hours;
        }
        var minutes = totalMinutes % 60;
        if (minutes < 10) {
            minutes = "0"+minutes;
        }
        return hours+":"+minutes;
    }

    function saveFinalScene(uiObj)
    {
        var scene = "";
        if (uiObj.selectedIndex > 0)
            scene = uiObj.options[uiObj.selectedIndex].value;
        var deusDevice = api.getCpanelDeviceId();
        api.setDeviceStatePersistent(deusDevice, serviceId, "FinalScene", scene, 0);
    }

    function clean(name, dflt)
    {
        if (dflt === undefined) dflt = '(undefined)';
        if (name === undefined) name = dflt;
        return name;
    }

    function getScenePairDisplay(onScene, offScene)
    {
        var html = "";
        var divid = 'S' + onScene.toString() + '-' + offScene.toString();
        html += '<li class="controlled-scenes" id="' + divid + '">';
        html += '<i class="material-icons w3-large cursor-hand color-red" onClick="DeusExMachinaII.removeScenePair(' + "'" + divid + "'" + ')">remove_circle_outline</i>';
        html += '&nbsp;On:&nbsp;' + clean(sceneNamesById[onScene], '(missing scene)') + '; Off:&nbsp;' + clean(sceneNamesById[offScene], '(missing scene)');
        html += '</li>'; // controlled
        return html;
    }

    function addScenePair(onScene, offScene)
    {
        var sceneSpec = 'S' + onScene.toString() + '-' + offScene.toString();
        var index = findControlledSceneSpec(sceneSpec);
        if (index < 0) {
            var html = getScenePairDisplay(onScene, offScene);
            jQuery('ul#scenepairs').append(html);
            updateControlledList();

            jQuery("select#addonscene").prop("selectedIndex", 0);
            jQuery("select#addoffscene").prop("selectedIndex", 0);
        }
    }

    function removeScenePair(spec)
    {
        var index = findControlledSceneSpec(spec);
        if (index >= 0) {
            jQuery('li#' + spec).remove();
            updateControlledList();
        }
    }

    function changeDeviceOnOff( ev )
    {
        var deviceId = jQuery( ev.target ).attr('id').substr(6);
        var index = findControlledDevice(deviceId);
        // console.log('checkbox ' + deviceId + ' in controlled at ' + index);
        // if index < 0 if device is currently not controlled, and we're turning it on. Otherwise the reverse.
        jQuery("input#device" + deviceId).prop("checked", index < 0);
        jQuery("div#slider" + deviceId).slider("option", "disabled", index >= 0);
        jQuery("input#ontime" + deviceId).prop('disabled', index >= 0);
        updateControlledList();
    }

    function changeDimmerSlider( obj, val )
    {
        // console.log('changeDimmerSlider(' + obj.attr('id') + ', ' + val + ')');
        var deviceId = obj.attr('id').substr(6);
        var ix = findControlledDevice(deviceId);
        if (ix >= 0) {
            controlled[ix] = deviceId + (val < 100 ? '=' + val : ""); // 100% is assumed if not specified
            updateControlledList();
        }
    }

    function changeOnTime( ev )
    {
        var newMax = jQuery(ev.target).val();
        if (!newMax.match(/^\s*$/)) {
            newMax = parseInt(newMax);
            if (isNaN(newMax) || newMax < 1) {
                alert('Invalid max; must be blank, or an integer > 0');
                jQuery(ev.target).val("");
            }
        }
        updateControlledList();
    }

    function changeHouseModeSelector( eventObject )
    {
        var mask = 0;
        jQuery(".hmselect:checked").each( function( i, e ) {
            mask |= (1 << jQuery(e).val());
        });
        var deusDevice = api.getCpanelDeviceId();
        api.setDeviceStatePersistent(deusDevice, serviceId, "HouseModes", mask, 0);
    }

    function checkTime(val)
    {
        var re = new RegExp("^([0-2]?[0-9]):([0-5][0-9])\s*$");
        var res = re.exec(val);
        if (res) {
            var hours = parseInt(res[1]);
            var minutes = parseInt(res[2]);
            if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
                return hours*60 + minutes;
            }
        }
        return -1;
    }
    
    function checkTimes(obj)
    {
        var deusDevice = api.getCpanelDeviceId();
        var s = jQuery("input#noauto").prop("checked");
        var startEl = jQuery("input#startTime");
        var endEl = jQuery("input#deusExTime");
        if ( s ) {
            startEl.prop('disabled', true);
            endEl.prop('disabled', true);
            api.setDeviceStatePersistent(deusDevice, serviceId, "AutoTiming", "0", 0);
        } else {
            api.setDeviceStatePersistent(deusDevice, serviceId, "AutoTiming", "1", 0);
            startEl.prop('disabled', false);
            var t = checkTime(startEl.val());
            if ( t > 0 ) {
                api.setDeviceStatePersistent(deusDevice, serviceId, "StartTime", t, 0);
            }
            endEl.prop('disabled', false);
            t = checkTime(endEl.val());
            if ( t > 0 ) {
                api.setDeviceStatePersistent(deusDevice, serviceId, "LightsOut", t, 0);
            }
        }
    }

    function checkMaxTargets(obj)
    {
        var maxt = jQuery(obj).val();
        var re = new RegExp("^[0-9]+$");
        if (re.exec(maxt)) {
            var deusDevice = api.getCpanelDeviceId();
            api.setDeviceStatePersistent(deusDevice, serviceId, "MaxTargetsOn", maxt, 0);
            return;
        }
        alert("Max On Targets must be an integer and >= 0");
        jQuery(obj).focus();
    }

    function saveStopAction(obj)
    {
        var sel = jQuery("select#stopaction").val();
        var deusDevice = api.getCpanelDeviceId();
        api.setDeviceStatePersistent(deusDevice, serviceId, "LeaveLightsOn", sel, 0);
    }

    function validateScene()
    {
        var s1 = document.getElementById("addonscene");
        var s2 = document.getElementById("addoffscene");
        if (s1.selectedIndex > 0 && s2.selectedIndex > 0)
            jQuery("#addscenebtn").removeClass( "color-gray" ).addClass( "color-green cursor-hand" );
        else
            jQuery("#addscenebtn").removeClass( "color-green cursor-hand" ).addClass( "color-gray" );
    }

    function doSceneAdd()
    {
        var s1 = document.getElementById("addonscene");
        var s2 = document.getElementById("addoffscene");
        if (s1.selectedIndex > 0 && s2.selectedIndex > 0)
            DeusExMachinaII.addScenePair(s1.options[s1.selectedIndex].value, s2.options[s2.selectedIndex].value);
    }

    ////////////////////////////
    function configureDeus()
    {
        try {
            init();

            var i, html = "";

            html += '<link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">';
            html += '<style>.material-icons { vertical-align: -20%; }';
            html += 'div.demcgroup { width: 286px; padding: 0px 24px 8px 0px; }';
            html += 'div.devicelist { }';
            html += 'div.scenecontrol { }';
            html += '.demslider { display: inline-block; width: 200px; height: 1em; border-radius: 8px; }';
            html += '.demslider .ui-slider-handle { background: url("/cmh/skins/default/img/other/slider_horizontal_cursor_24.png?") no-repeat scroll left center rgba(0,0,0,0); cursor: pointer !important; height: 24px !important; width: 24px !important; margin-top: 6px; font-size: 12px; text-align: center; padding-top: 4px; text-decoration: none; }';
            html += '.demslider .ui-slider-range-min { background-color: #12805b !important; }';
            html += 'ul#scenepairs { list-style: none; }';
            html += '.cursor-hand { cursor: pointer; }';
            html += '.color-red { color: #ff0000; }';
            html += '.color-green { color: #12805b; }';
            html += '.color-gray { color: #999999; }';
            html += 'input#startTime { text-align: center; }';
            html += 'input#deusExTime { text-align: center; }';
            html += 'input#maxtargets { text-align: center; }';
            html += 'input.ontime { width: 48px; text-align: center; }';
            html += '</style>';

            // Start Time
            html += '<div class="demcgroup pull-left">';
            html += "<h2>Auto-Activation</h2>";
            html += 'Set the approximate start and stop times for cycling. If the start time is left blank, it will be sunset. The actual start and stop times will be delayed randomly.<br/>';
            html += '<input type="checkbox" value="1" id="noauto" onChange="DeusExMachinaII.checkTimes(this)">Manual Activation (e.g. action from Reactor or Lua)<br/>';
            html += 'From: <input type="text" size="7" maxlength="5" onChange="DeusExMachinaII.checkTimes(this)" id="startTime">';
            html += " to <input type=\"text\" size=\"7\" maxlength=\"5\" onChange=\"DeusExMachinaII.checkTimes(this)\" id=\"deusExTime\" /> (HH:MM)";
            html += '</div>';

            // House Modes
            html += '<div class="demcgroup pull-left">';
            html += "<h2>House Modes</h2>";
            html += "When enabled, lights cycle <i>only</i> in these House Modes (if all unchecked, runs in any mode):<br/>";
            html += '<input type="checkbox" id="mode1" class="hmselect" name="houseMode" value="1" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Home</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode2" class="hmselect" name="houseMode" value="2" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Away</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode3" class="hmselect" name="houseMode" value="3" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Night</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode4" class="hmselect" name="houseMode" value="4" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Vacation</input>';
            html += '</div>';

            // Maximum number of targets allowed to be "on" simultaneously
            html += '<div class="demcgroup pull-left">';
            html += "<h2>Maximum \"On\" Targets</h2>Maximum number of controlled devices and scenes (targets) that can be \"on\" at once:<br/>";
            html += "<input type=\"text\" size=\"5\" onChange=\"DeusExMachinaII.checkMaxTargets(this)\" id=\"maxtargets\" />&nbsp;(0=no limit)";
            html += '</div>';

            // Final scene (the scene that is run when everything has been turned off and DEM is going idle).
            html += '<div id="demfinalscene" class="demcgroup pull-left"><h2>Final Scene</h2>If specified, this scene is run after all other targets have been turned off during a lights-out cycle:<br/><select id="finalscene" onChange="DeusExMachinaII.saveFinalScene(this)"><option value="">(none)</option>';
            html += '</select></div>';

            // Final scene (the scene that is run when everything has been turned off and DEM is going idle).
            html += '<div class="demcgroup pull-left"><h2>Stop Action</h2>While DEMII is running, if the house mode changes to an unselected mode, or DEMII is disabled, then:<br/><select id="stopaction" onChange="DeusExMachinaII.saveStopAction(this)"><option value="0">Turn controlled lights off</option>';
            html += '<option value="1">Leave lights as they are</a>';
            html += '</select></div>';

            html += '<div class="clearfix"></div>';

            // Controlled Devices
            var devices = api.getListOfDevices();
            var rooms = [];
            var noroom = { "id": "0", "name": "No Room", "devices": [] };
            rooms[noroom.id] = noroom;
            for (i=0; i<devices.length; i+=1) {
                if (isControllable(devices[i].id)) {
                    var roomid = devices[i].room || "0";
                    var roomObj = rooms[roomid];
                    if ( roomObj === undefined ) {
                        roomObj = api.cloneObject(api.getRoomObject(roomid));
                        roomObj.devices = [];
                        rooms[roomid] = roomObj;
                    }
                    roomObj.devices.push(devices[i]);
                }
            }

            var r = rooms.sort(
                // Special sort for room name -- sorts "No Room" last
                function (a, b) {
                    if (a.id === 0) return 1;
                    if (b.id === 0) return -1;
                    if (a.name === b.name) return 0;
                    return a.name > b.name ? 1 : -1;
                }
            );

            html += '<div id="devicelist">';
            html += '<h2>Controlled Devices</h2>Select the devices to be controlled. If the "Max On Time" is set, the device will not be allowed to be on for more than that many consecutive minutes; blank (default) means no limit. You can set level for dimmable devices.';
            html += '<div id="devs" class="table-responsive">';
            controlled = getControlledList();
            html += "<table class='table'>";
            html += '<thead>';
            html += '<tr><th>Device</th><th>Max "On" Time</th><th>Level</th></tr>';
            html += '</thead><tbody>';
            r.forEach( function( roomObj ) {
                if ( roomObj.devices && roomObj.devices.length ) {
                    html += '<tr class="success"><td colspan="3">' + roomObj.name + '</td></tr>';
                    for (i=0; i<roomObj.devices.length; i+=1) {
                        html += '<tr>'; // row-like
                            html += '<td class="col-xs-3">';
                            html += '<input class="controlled-device" id="device' + roomObj.devices[i].id + '" type="checkbox"';
                            if (DeusExMachinaII.findControlledDevice(roomObj.devices[i].id) >= 0)
                                html += ' checked="true"';
                            html += ">";
                            html += "&nbsp;#" + roomObj.devices[i].id + " ";
                            html += roomObj.devices[i].name;
                            html += "</td>";
                            html += '<td class="col-xs-2">';
                            html += '<input class="ontime" id="ontime' + roomObj.devices[i].id + '">';
                            html += '</td>';
                            html += '<td>';
                            if (isDimmer(roomObj.devices[i].id)) html += '<div class="demslider" id="slider' + roomObj.devices[i].id + '"></div>';
                            html += '</td>';
                        html += "</tr>\n"; // row-like
                    }
                }
            });
            html += "</tbody></table>";
            html += "</div>";   // devs

            // Scene Control
            html += '<div id="scenecontrol"><h2>Scene Control</h2>';
            html += 'In addition to controlling individual devices, DeusExMachinaII can run scenes. Scenes are specified in pairs: a scene to do something (the "on" scene), and a scene to undo it (the "off" scene). To add a scene pair, select an "on" scene and an "off" scene and click the green plus. To remove a configured scene pair, click the red minus next to it.<br/>';
            html += '<label>Add Scene Pair:</label> "On"&nbsp;Scene:<select id="addonscene" onChange="DeusExMachinaII.validateScene()"><option value="">--choose--</option>';
            html += '</select> "Off"&nbsp;Scene:<select id="addoffscene" onChange="DeusExMachinaII.validateScene()"><option value="">--choose--</option>';
            html += '</select>';
            html += '&nbsp;<i class="material-icons w3-large color-gray" id="addscenebtn" onClick="DeusExMachinaII.doSceneAdd()">add_circle_outline</i>';
            html += '<ul id="scenepairs"></ul>';
            html += '</div>';

            html += '<h2>More Information</h2>If you need more information about configuring DeusExMachinaII, please see the <a href="https://github.com/toggledbits/DeusExMachina/blob/master/README.md" target="_blank">README</a> in <a href="https://github.com/toggledbits/DeusExMachina" target="_blank"> our GitHub repository</a>.<p><b>Find DeusExMachinaII useful?</b> Please consider supporting the project with <a href="https://www.toggledbits.com/donate">a small donation</a>. I am grateful for any support you choose to give!</p>';

            // Push generated HTML to page
            api.setCpanelContent(html);

            var deusDevice = api.getCpanelDeviceId();

            // Restore time fields
            var timeMins = parseInt(api.getDeviceState(deusDevice, serviceId, "LightsOut"));
            var time = isNaN(timeMins) ? "23:59" : timeMinsToStr(timeMins);
            jQuery("input#deusExTime").val(time);

            timeMins = parseInt(api.getDeviceState(deusDevice, serviceId, "StartTime"));
            time = isNaN(timeMins) ? "" : timeMinsToStr(timeMins);
            jQuery("input#startTime").val(time);

            var autoTiming = parseInt(api.getDeviceState(deusDevice, serviceId, "AutoTiming"));
            var manual = ( !isNaN(autoTiming) ) && autoTiming == 0;
            jQuery("input#noauto").prop("checked", manual);
            jQuery("input#deusExTime").prop("disabled", manual);
            jQuery("input#startTime").prop("disabled", manual);

            // Restore maxtargets
            var maxt = parseInt(api.getDeviceState(deusDevice, serviceId, "MaxTargetsOn"));
            if (isNaN(maxt) || maxt < 0)
                maxt = 0;
            jQuery("#maxtargets").val(maxt);

            // Restore house modes
            var houseModes = parseInt(api.getDeviceState(deusDevice, serviceId, "HouseModes"));
            for (var k=1; k<=4; ++k) {
                if (houseModes & (1<<k)) jQuery('input#mode' + k).prop('checked', true);
            }

            // Restore stop action
            var leaveOn = parseInt(api.getDeviceState(deusDevice, serviceId, "LeaveLightsOn"));
            if (!isNaN(leaveOn))
                jQuery('select#stopaction option[value="' + leaveOn + '"]').prop('selected', true);


            // Activate dimmer sliders. Mark all disabled, then enable those for checked dimmers
            jQuery('.demslider').slider({
                min: 5,
                max: 100,
                step: 5,
                range: "min",
                stop: function ( ev, ui ) {
                    DeusExMachinaII.changeDimmerSlider( jQuery(this), ui.value );
                },
                slide: function( ev, ui ) {
                    jQuery( 'a.ui-slider-handle', jQuery( this ) ).text( ui.value );
                },
                change: function( ev, ui ) {
                    jQuery( 'a.ui-slider-handle', jQuery( this ) ).text( ui.value );
                }
            });
            jQuery('.demslider').slider("option", "disabled", true);
            jQuery('.demslider').slider("option", "value", 100);
            jQuery('.demslider').each( function( ix, obj ) {
                var id = jQuery(obj).attr('id');
                id = id.substr(6);
                jQuery('input#device'+id+':checked').each( function() {
                    // Corresponding checked checkbox, enable slider.
                    jQuery(obj).slider("option", "disabled", false);
                    var ix = DeusExMachinaII.findControlledDevice(id);
                    if (ix >= 0) {
                        var info = DeusExMachinaII.getControlled(ix);
                        jQuery(obj).slider("option", "value", info.type == "device" ? info.value : 100);
                    }
                });
            });

            // Max On Time fields
            jQuery('input.ontime').prop('disabled', true);
            jQuery('input.ontime').each( function( ix, obj ) {
                var id = jQuery(obj).attr('id').substr(6);
                if ( jQuery('input#device'+id).prop('checked') ) {
                    jQuery("input#ontime"+id).prop('disabled', false);
                    var ix = DeusExMachinaII.findControlledDevice(id);
                    if (ix >= 0) {
                        var info = DeusExMachinaII.getControlled(ix);
                        if (info.maxon != null) jQuery(obj).val(info.maxon);
                    }
                }
            });
            jQuery('input.ontime').change( changeOnTime );

            jQuery('input.controlled-device').change( changeDeviceOnOff );

            // Load sdata to get scene list. Populate menus, load controlled scene pairs, final scene.
            jQuery.ajax({
                url: api.getDataRequestURL(),
                data: { 'id' : 'sdata' },
                dataType: 'json',
                success: function( data, status ) {
                    var menu = "";
                    sceneNamesById = [];
                    jQuery.each( data.scenes, function( ix, obj ) {
                        menu += '<option value="' + obj.id + '">' + obj.name + '</option>';
                        sceneNamesById[obj.id] = obj.name;
                    });
                    jQuery('select#addonscene').append(menu);
                    jQuery('select#addoffscene').append(menu);
                    validateScene();

                    for (var k=0; k<controlled.length; ++k) {
                        var t = DeusExMachinaII.getControlled(k);
                        if (t !== undefined && t.type == "scene")
                            jQuery('ul#scenepairs').append( DeusExMachinaII.getScenePairDisplay(t.onScene, t.offScene) );
                    }

                    jQuery('select#finalscene').append(menu);
                    var fs = api.getDeviceState(deusDevice, serviceId, "FinalScene");
                    if (fs !== undefined) jQuery('select#finalscene option[value="' + fs + '"]').prop('selected', true);
                }
            });
        }
        catch (e)
        {
            console.log("Error in DeusExMachinaII.configureDeus(): " + e);
            Utils.logError('Error in DeusExMachinaII.configureDeus(): ' + e);
        }
    }

    myModule = {
        uuid: uuid,
        init: init,
        onBeforeCpanelClose: onBeforeCpanelClose,
        changeHouseModeSelector: changeHouseModeSelector,
        checkTimes: checkTimes,
        checkMaxTargets: checkMaxTargets,
        saveStopAction: saveStopAction,
        changeDeviceOnOff: changeDeviceOnOff,
        configureDeus: configureDeus,
        addScenePair: addScenePair,
        removeScenePair: removeScenePair,
        saveFinalScene: saveFinalScene,
        getScenePairDisplay: getScenePairDisplay,
        changeDimmerSlider: changeDimmerSlider,
        findControlledDevice: findControlledDevice,
        getControlled: getControlled,
        validateScene: validateScene,
        doSceneAdd: doSceneAdd
    };
    return myModule;
})(api, $ || jQuery);