//# sourceURL=J_DeusExMachinaII1_UI7.js
/** 
 * J_DeusExMachinaII1.js
 * Configuration interface for DeusExMachinaII on pre-UI7 firmware.
 *
 * Copyright 2016,2017 Patrick H. Rigney, All Rights Reserved.
 * This file is part of DeusExMachinaII. For license information, see LICENSE at https://github.com/toggledbits/DeusExMachina
 */
var configureDeus;
var updateDeusControl;
var checkTime;

(function() {
    var serviceId = "urn:toggledbits-com:serviceId:DeusExMachinaII1";
    var controlled;
    var deusDevice;

    configureDeus = function(thisDeusDevice) {
        deusDevice = thisDeusDevice;
        var devices = jsonp.ud.devices;
        var html = "<p>Select the lights to be controlled when enabled.</p>";

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
        controlled = getControlled();

        for (var i=0; i<devices.length; i++) {
            if (isLight(devices[i])) {
                html += "<input type=\"checkbox\"";
                if (jQuery.inArray(devices[i].id, controlled) >= 0) {
                    html += " checked=\"true\"";
                }
                html += " onChange=\"updateDeusControl('"+devices[i].id+"')\"";
                html += " />";
                html += devices[i].name+"<br />";
            }
        }
        var time = "23:59";
        var timeMins = parseInt(get_device_state(deusDevice, serviceId, "LightsOut", 0));
        if (!isNaN(timeMins)) {
            time = timeMinsToStr(timeMins);
        }

        html += "<br />";
        html += "<p>Enter the time (after sunset) to begin shutting off lights</p>";
        html += "<input type=\"text\" onChange=\"checkTime()\" id=\"deusExTime\" /> (HH:MM)";
        set_panel_html(html);
        jQuery("#deusExTime").val(time);
    };

    updateDeusControl = function(deviceId) {
        var index = jQuery.inArray(deviceId, controlled);
        if (index >= 0) {
            controlled.splice(index, 1);

        } else {
            controlled.push(deviceId);
        }

        set_device_state(deusDevice, serviceId, "Devices", controlled.join(','), 0);
    };

    function timeMinsToStr(totalMinutes) {
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

    function updateTime(timeMins) {
        set_device_state(deusDevice, serviceId, "LightsOut", timeMins, 0);
    }

    checkTime = function() {
        var time = jQuery("#deusExTime").val();
        var re = new RegExp("^([0-2][0-9]):([0-6][0-9])$");
        var res = re.exec(time);
        if (res) {
            var hours = parseInt(res[1]);
            var minutes = parseInt(res[2]);
            if (hours <= 23 && minutes <= 59) {
                updateTime(hours * 60 + minutes);
                return;
            }
        }
        alert("Time must be in the format HH:MM (i.e. 22:30)");
    };
})();
