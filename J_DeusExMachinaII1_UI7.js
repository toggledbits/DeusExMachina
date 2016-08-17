var DeusExMachinaII = (function(api) {

    // unique identifier for this plugin...
    var uuid = '11816AA9-0C7C-4E8F-B490-AAB429FA140F';

    var serviceId = "urn:toggledbits-com:serviceId:DeusExMachinaII1";

    var myModule = {};

    var deusDevice = api.getCpanelDeviceId();
    var controlled;

    function onBeforeCpanelClose(args) {
        console.log('handler for before cpanel close');
    }

    function init() {
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }

    function isLight(device) {
        switch(device.device_type) {
            case "urn:schemas-upnp-org:device:BinaryLight:1":
            case "urn:schemas-upnp-org:device:DimmableLight:1":
                return true;

            default:
                return false;
        }
    }

    function getControlled() {
        var list = get_device_state(deusDevice, serviceId, "Devices", 0);
        if (typeof(list) == "undefined" || list.match(/^\s*$/)) {
            return [];
        }
        var res = list.split(',');
        return res;
    }

    function timeMsToStr(ms)
    {
        var totalMinutes = ms / 1000 / 60;
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

    function updateTime(timeMs)
    {
        api.setDeviceStatePersistent(deusDevice, serviceId, "LightsOutTime", timeMs, 0); // PHR 01
    }

    function updateDeusControl(deviceId)
    {
        var index = jQuery.inArray(deviceId.toString(), controlled); // PHR 03
        if (index >= 0) {
            controlled.splice(index, 1);

        } else {
            controlled.push(deviceId);
        }

        api.setDeviceStatePersistent(deusDevice, serviceId, "Devices", controlled.join(','), 0); // PHR 01
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
            if (hours <= 23 && minutes <= 59) {
                var totalMinutes = hours * 60 + minutes;
                var totalSeconds = totalMinutes * 60;
                var totalMs = totalSeconds * 1000;
                updateTime(totalMs);
                return;
            }
        }
        alert("Time must be in the format HH:MM (i.e. 22:30)");
    }

    ////////////////////////////
    function configureDeus()
    {
        try {
            init();

            var i, j, roomObj, roomid, html = "";
            html += "<label for=\"deusExTime\">Enter the time (after sunset) to begin shutting off lights:</label><br/>";
            html += "<input type=\"text\" size=\"6\" maxlength=\"5\" onChange=\"DeusExMachinaII.checkTime()\" id=\"deusExTime\" />&nbsp;(HH:MM)";
            
            html += "<p>";
            html += "<label for=\"houseMode\">When enabled, run <i>only</i> in these House Modes (if all unchecked, runs in any mode):</label><br/>";
            html += '<input type="checkbox" id="mode1" class="hmselect" name="houseMode" value="1" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Home</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode2" class="hmselect" name="houseMode" value="2" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Away</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode3" class="hmselect" name="houseMode" value="3" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Night</input>';
            html += '&nbsp;&nbsp;<input type="checkbox" id="mode4" class="hmselect" name="houseMode" value="4" onChange="DeusExMachinaII.changeHouseModeSelector(this);">&nbsp;Vacation</input>';
            html += "</p>";

            var devices = api.getListOfDevices();
            var rooms = [];
            var noroom = { "id": "0", "name": "No Room", "devices": [] };
            rooms[noroom.id] = noroom;
            for (i=0; i<devices.length; i+=1) {
                if (isLight(devices[i])) {
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

            html += "<p>&nbsp;</p><div><label for=\"controlled\">Select the devices to be controlled when enabled:</label>";
            controlled = getControlled();
            for (j=0; j<r.length; j+=1) {
                roomObj = r[j];
                if (roomObj === undefined || roomObj.devices.length == 0) continue; // skip gaps in our sparse list, and rooms with no devices
                roomid = roomObj.id;
                html += '<div class="room_container_header_title">' + roomObj.name + "</div>";
                for (i=0; i<roomObj.devices.length; i+=1) {
                    html += "<input id=\"controlled\" type=\"checkbox\"";
                    if (jQuery.inArray(roomObj.devices[i].id.toString(), controlled) >= 0) { // PHR 03
                        html += " checked=\"true\"";
                    }
                    html += " onChange=\"DeusExMachinaII.updateDeusControl('" + roomObj.devices[i].id + "')\"";
                    html += " />&nbsp;";
                    html += "#" + roomObj.devices[i].id + " ";
                    html += roomObj.devices[i].name;
                    html += "<br />\n";
                }
            }
            html += "</div>";

            // Finish up
            
            api.setCpanelContent(html);
            
            // Restore time field
            var time = "23:59";
            var timeMs = parseInt(api.getDeviceState(deusDevice, serviceId, "LightsOutTime"));
            if (!isNaN(timeMs))
            {
                time = timeMsToStr(timeMs);
            }
            jQuery("#deusExTime").val(time);
            
            // Restore house modes
            var houseModes = parseInt(api.getDeviceState(deusDevice, serviceId, "HouseModes"));
            for (var k=1; k<=4; ++k) {
                if (houseModes & (1<<k)) jQuery('input#mode' + k).attr('checked', true);
            }
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
        updateDeusControl: updateDeusControl,
        configureDeus: configureDeus
    };
    return myModule;
})(api);

//*****************************************************************************
// Extension of the Array object:
//  indexOf : return the index of a given element or -1 if it doesn't exist
//*****************************************************************************
if (!Array.prototype.indexOf) {
    Array.prototype.indexOf = function (element /*, from*/) {
        var len = this.length;

        var from = Number(arguments[1]) || 0;
        if (from < 0) {
            from += len;
        }

        for (; from < len; from++) {
            if (from in this && this[from] === element) {
                return from;
            }
        }
        return -1;
    };
}
