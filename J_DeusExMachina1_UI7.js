var DeusExMachina = (function(api) {

/* **************************************************************************************
Patrick Rigney (rigpapa) bug fixes 2016-05-06

PHR 03: jQuery.inArray() requires type match, so make sure any numeric value passed into
        the search is a string, because that's what we're usually looking for in the
        array.
PHR 02: Wrong variable name used, seems copied from MCV template; changed to correct name
PHR 01: MCV examples all supply 0 as last argument (for unsupplied optional args). Also
        use setDeviceStatePersistent to make settings stick.

************************************************************************************** */

    // unique identifier for this plugin...
    // var uuid = '07EE8EAA-739D-4CEE-97E4-7C2B651A03A6';
	var uuid = '11816aa9-0c7c-4e8f-b490-aab429fa140f';

    var serviceId = "urn:toggledbits-com:serviceId:DeusExMachina1";

    var myModule = {};

    var deusDevice = api.getCpanelDeviceId();
    var controlled;
    ////////////////////////////
    function onBeforeCpanelClose(args) {
        console.log('handler for before cpanel close');
    }

    function init() {
        // register to events...
        api.registerEventHandler('on_ui_cpanel_before_close', myModule, 'onBeforeCpanelClose');
    }

    function isLight(device) {
        switch(device.device_type) {
        case "urn:schemas-upnp-org:device:BinaryLight:1":
            return true;

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
            html += "<input type=\"text\" onChange=\"DeusExMachina.checkTime()\" id=\"deusExTime\" />&nbsp;(HH:MM)";

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

            html += "<p>Select the lights to be controlled when enabled.</p>";
            controlled = getControlled();
            for (j=0; j<r.length; j+=1) {
                roomObj = r[j];
                if (roomObj === undefined || roomObj.devices.length == 0) continue; // skip gaps in our sparse list, or rooms with no devices
                roomid = roomObj.id;
                html += '<div class="room_container_header_title">' + roomObj.name + "</div>";
                for (i=0; i<roomObj.devices.length; i+=1) {
                    html += "<input type=\"checkbox\"";
                    if (jQuery.inArray(roomObj.devices[i].id.toString(), controlled) >= 0) { // PHR 03
                        html += " checked=\"true\"";
                    }
                    html += " onChange=\"DeusExMachina.updateDeusControl('" + roomObj.devices[i].id + "')\"";
                    html += " />&nbsp;";
                    html += "#" + roomObj.devices[i].id + " ";
                    html += roomObj.devices[i].name;
                    html += "<br />\n";
                }
            }

            var time = "23:59";
            var timeMs = parseInt(api.getDeviceState(deusDevice, serviceId, "LightsOutTime"));
            if (!isNaN(timeMs))
            {
                time = timeMsToStr(timeMs);
            }

            api.setCpanelContent(html);
            jQuery("#deusExTime").val(time);
        }
        catch (e)
        {
            Utils.logError('Error in DeusExMachina.configureDeus(): ' + e);
        }
    }

    myModule = {
        uuid: uuid,
        init: init,
        onBeforeCpanelClose: onBeforeCpanelClose,
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