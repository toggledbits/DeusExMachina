var DeusExMachinaII = (function(api) {

    // unique identifier for this plugin...
    var uuid = '11816AA9-0C7C-4E8F-B490-AAB429FA140F';

    var serviceId = "urn:toggledbits-com:serviceId:DeusExMachinaII1";

    var myModule = {};

    var deusDevice = api.getCpanelDeviceId();
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
		if (isDimmer(devid)) return true; /* a dimmer is a light */
		var v = api.getDeviceState( devid, "urn:upnp-org:serviceId:SwitchPower1", "Status" );
		if (v === undefined || v === false) return false;
		return true;
    }

    function getControlledList() {
        var list = get_device_state(deusDevice, serviceId, "Devices", 0);
        if (typeof(list) == "undefined" || list.match(/^\s*$/)) {
            return [];
        }
        return list.split(',');
    }
    
    function updateControlledList() {
        controlled = [];
        jQuery('input.controlled-device:checked').each( function( ix, obj ) {
            var devid = jQuery(obj).attr('id').substr(6);
            var level = 100;
            var ds = jQuery('div#slider' + devid);
            if (ds.length == 1) 
                level = ds.slider('option','value');
            if (level < 100)
                devid += '=' + level;
            controlled.push(devid);
        });
        jQuery('.controlled-scenes').each( function( ix, obj ) {
            var devid = jQuery(obj).attr('id');
            // console.log('updateControlledList: handling scene pair ' + devid);
            controlled.push(devid);
        });
                
        var s = controlled.join(',');
        // console.log('Updating controlled list to ' + s);
        api.setDeviceStatePersistent(deusDevice, serviceId, "Devices", s, 0);
    }
    
    // Find a controlled device in the Devices list
    function findControlledDevice(deviceId)
    {
        for (var k=0; k<controlled.length; ++k) {
            if (controlled[k].charAt(0) != 'S') { // skip scene control
                // Handle dev=dimlevel syntax
                var l = controlled[k].indexOf('=');
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
        ret.index = ix;
        ret.raw = c;
        if (c.charAt(0) == 'S') {
            ret.type = "scene";
            var l = c.indexOf('-');
            ret.onScene = c.substr(1,l-1); // portion after S and before -
            ret.offScene = c.substr(l+1); // after -
        } else {
            ret.type = "device";
            var l = c.indexOf('=');
            var d,v
            if (l < 0) {
                d = c;
                v = 100;
            } else {
                d = c.substr(0,l);
                v = c.substr(l+1);
            }
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

    function updateTime(timeMins)
    {
        api.setDeviceStatePersistent(deusDevice, serviceId, "LightsOut", timeMins, 0);
    }
    
    function saveFinalScene(uiObj) 
    {
        var scene = "";
        if (uiObj.selectedIndex > 0) 
            scene = uiObj.options[uiObj.selectedIndex].value;
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
    
    function updateDeusControl(deviceId)
    {
        var index = findControlledDevice(deviceId);
        // console.log('checkbox ' + deviceId + ' in controlled at ' + index);
        if (index >= 0) {
            // Remove device
            jQuery("input#device" + deviceId).prop("checked", false);
            jQuery("div#slider" + deviceId).slider("option", "disabled", true);
            jQuery("div#slider" + deviceId).slider("option", "value", 1);
        } else {
            // Add device
            jQuery("input#device" + deviceId).prop("checked", true);
            jQuery("div#slider" + deviceId).slider("option", "disabled", false);
            jQuery("div#slider" + deviceId).slider("option", "value", 100);
        }
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
    
    function changeHouseModeSelector( eventObject ) 
    {
        var mask = 0;
        jQuery(".hmselect:checked").each( function( i, e ) {
            mask |= 1 << jQuery(e).val();
        });
        api.setDeviceStatePersistent(deusDevice, serviceId, "HouseModes", mask, 0);
    }

    function checkTime()
    {
        var time = jQuery("#deusExTime").val();
        var re = new RegExp("^([0-2]?[0-9]):([0-5][0-9])$");
        var res = re.exec(time);
        if (res) {
            var hours = parseInt(res[1]);
            var minutes = parseInt(res[2]);
            if (hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
                updateTime(hours * 60 + minutes);
                return;
            }
        }
        alert("Time must be in the format HH:MM (i.e. 22:30)");
    }
    
    function checkMaxTargets()
    {
        var maxt = jQuery("#maxtargets").val();
        var re = new RegExp("^[0-9]+$");
        if (re.exec(maxt)) {
            api.setDeviceStatePersistent(deusDevice, serviceId, "MaxTargetsOn", maxt, 0);
            return;
        }
        alert("Max On Targets must be an integer and >= 0");
    }

    ////////////////////////////
    function configureDeus()
    {
        try {
            init();

            var i, j, roomObj, roomid, html = "";
            
            html += '<script>function validateScene() { var s1 = document.getElementById("addonscene"); var s2 = document.getElementById("addoffscene"); document.getElementById("addscenebtn").disabled = !(s1.selectedIndex > 0 && s2.selectedIndex > 0); }';
            html += 'function dosceneadd() { var s1 = document.getElementById("addonscene"); var s2 = document.getElementById("addoffscene"); if (s1.selectedIndex > 0 && s2.selectedIndex > 0) DeusExMachinaII.addScenePair(s1.options[s1.selectedIndex].value, s2.options[s2.selectedIndex].value); }';
            html += '</script>';
            html += '<link rel="stylesheet" href="https://fonts.googleapis.com/icon?family=Material+Icons">';
            html += '<style>.material-icons { vertical-align: -20%; }';
            html += '.demslider { display: inline-block; width: 200px; height: 1em; border-radius: 8px; position: absolute; left: 300px;}';
            html += '.demslider .ui-slider-handle { background: url("/cmh/skins/default/img/other/slider_horizontal_cursor_24.png?") no-repeat scroll left center rgba(0,0,0,0); cursor: pointer !important; height: 24px !important; width: 24px !important; margin-top: 6px; }';
            html += '.demslider .ui-slider-range-min { background-color: #12805b !important; }';
            html += 'ul#scenepairs { list-style: none; }';
            html += '.cursor-hand { cursor: pointer; }';
            html += '.color-red { color: #ff0000; }';
            html += '.color-green { color: #12805b; }';
            html += 'input#deusExTime { text-align: center; }';
            html += 'input#maxtargets { text-align: center; }';
            html += '</style>';
            
            html += "<h2>Lights-Out Time</h2><label for=\"deusExTime\">Lights will cycle between sunset and the \"lights-out\" time. Enter the time to begin shutting off lights:</label><br/>";
            html += "<input type=\"text\" size=\"7\" maxlength=\"5\" onChange=\"DeusExMachinaII.checkTime()\" id=\"deusExTime\" />&nbsp;(HH:MM)";
            
            html += "<h2>House Modes</h2>";
            html += "<label for=\"houseMode\">When enabled, lights cycle <i>only</i> in these House Modes (if all unchecked, runs in any mode):</label><br/>";
            html += '<input type="checkbox" id="mode1" class="hmselect" name="houseMode" value="1" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Home</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode2" class="hmselect" name="houseMode" value="2" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Away</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode3" class="hmselect" name="houseMode" value="3" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Night</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode4" class="hmselect" name="houseMode" value="4" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Vacation</input>';

            var devices = api.getListOfDevices();
            var rooms = [];
            var noroom = { "id": "0", "name": "No Room", "devices": [] };
            rooms[noroom.id] = noroom;
            for (i=0; i<devices.length; i+=1) {
				if (isControllable(devices[i].id)) {
                    roomid = devices[i].room;
                    roomObj = rooms[roomid];
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
                    if (a.id == 0) return 1;
                    if (b.id == 0) return -1;
                    if (a.name === b.name) return 0;
                    return a.name > b.name ? 1 : -1;
                }
            );

            html += "<h2>Controlled Devices</h2><div id='devs'><label>Select the devices to be controlled:</label>";
            controlled = getControlledList();
            for (j=0; j<r.length; j+=1) {
                roomObj = r[j];
                if (roomObj === undefined || roomObj.devices.length == 0) continue; // skip gaps in our sparse list, and rooms with no devices
                roomid = roomObj.id;
                html += '<h3>' + roomObj.name + "</h3>";
                for (i=0; i<roomObj.devices.length; i+=1) {
                    html += '<input class="controlled-device" id="device' + roomObj.devices[i].id + '" type="checkbox"';
                    if (DeusExMachinaII.findControlledDevice(roomObj.devices[i].id) >= 0)
                        html += ' checked="true"';
                    html += " onChange=\"DeusExMachinaII.updateDeusControl('" + roomObj.devices[i].id + "')\"";
                    html += " />&nbsp;";
                    html += "#" + roomObj.devices[i].id + " ";
                    html += roomObj.devices[i].name;
                    if (isDimmer(roomObj.devices[i].id)) html += '<div class="demslider" id="slider' + roomObj.devices[i].id + '"></div>';
                    html += "<br />\n";
                }
            }
            html += "</div>";   // devs
            
            // Handle scene pairs
            html += '<div id="scenes"><h2>Scene Control</h2>';
            html += 'In addition to controlling individual devices, DeusExMachinaII can run scenes. Scenes are specified in pairs: a scene to do something (the "on" scene), and a scene to undo it (the "off" scene). To add a scene pair, select an "on" scene and an "off" scene and click the green plus. To remove a configured scene pair, click the red minus next to it.';
            html += '<label>Add Scene Pair: On&nbsp;Scene:<select id="addonscene" onChange="validateScene()"><option value="">--choose--</option>';
            html += '</select> Off&nbsp;Scene:<select id="addoffscene" onChange="validateScene()"><option value="">--choose--</option>';
            html += '</select>';
            html += '&nbsp;<i class="material-icons w3-large color-green cursor-hand" id="addscenebtn" onClick="dosceneadd()">add_circle_outline</i>'
            html += '<ul id="scenepairs"></ul>';
            html += '</div>';

            // Maximum number of targets allowed to be "on" simultaneously
            html += "<h2>Maximum \"On\" Targets</h2><label for=\"maxtargets\">Maximum number of controlled devices and scenes (targets) that can be \"on\" at once:</label><br/>";
            html += "<input type=\"text\" size=\"5\" onChange=\"DeusExMachinaII.checkMaxTargets()\" id=\"maxtargets\" />&nbsp;(0=no limit)";

            // Final scene (the scene that is run when everything has been turned off and DEM is going idle).
            html += '<div id="demfinalscene"><h2>Final Scene</h2>The final scene, if specified, is run after all other targets have been turned off during a lights-out cycle.<br/><label for="finalscene">Final Scene:</label><select id="finalscene" onChange="DeusExMachinaII.saveFinalScene(this)"><option value="">(none)</option>';
            html += '</select></div>';
            
            html += '<h2>More Information</h2>If you need more information about configuring DeusExMachinaII, please see the <a href="https://github.com/toggledbits/DeusExMachina/blob/master/README.md" target="_blank">README</a> in <a href="https://github.com/toggledbits/DeusExMachina" target="_blank"> our GitHub repository</a>.';

            // Push generated HTML to page
            api.setCpanelContent(html);
          
            // Restore time field
            var time = "23:59";
            var timeMins = parseInt(api.getDeviceState(deusDevice, serviceId, "LightsOut"));
            if (!isNaN(timeMins))
                time = timeMinsToStr(timeMins);
            jQuery("#deusExTime").val(time);

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

            // Activate dimmer sliders. Mark all disabled, then enable those for checked dimmers
            jQuery('.demslider').slider({ 
                min: 1, 
                max: 100, 
                range: "min",
                stop: function ( event, ui ) {
                    DeusExMachinaII.changeDimmerSlider( jQuery(this), ui.value );
                }
            });
            jQuery('.demslider').slider("option", "disabled", true);
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

            // Load sdata to get scene list. Populate menus, load controlled scene pairs, final scene.
            jQuery.ajax({
                url: api.getDataRequestURL(),
                data: { 'id' : 'sdata' },
                dataType: 'json',
                success: function( data, status ) {
                    var menu = "";
                    /* global */ sceneNamesById = [];
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
                    var final = api.getDeviceState(deusDevice, serviceId, "FinalScene");
                    if (final !== undefined) jQuery('select#finalscene option[value="' + final + '"]').prop('selected', true);
                }
            });
        }
        catch (e)
        {
            Utils.logError('Error in DeusExMachinaII.configureDeus(): ' + e);
        }
    }

    myModule = {
        uuid: uuid,
        init: init,
        onBeforeCpanelClose: onBeforeCpanelClose,
        changeHouseModeSelector: changeHouseModeSelector,
        checkTime: checkTime,
        checkMaxTargets: checkMaxTargets,
        updateDeusControl: updateDeusControl,
        configureDeus: configureDeus,
        addScenePair: addScenePair,
        removeScenePair: removeScenePair,
        saveFinalScene: saveFinalScene,
        getScenePairDisplay: getScenePairDisplay,
        changeDimmerSlider: changeDimmerSlider,
        findControlledDevice: findControlledDevice,
        getControlled: getControlled
    };
    return myModule;
})(api);