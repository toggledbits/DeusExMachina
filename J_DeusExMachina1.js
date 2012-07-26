var configureDeus;
var updateDeusControl;
var checkTime;

(function() {
	var serviceId = "urn:futzle-com:serviceId:DeusExMachina1";
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
			var count = get_device_state(deusDevice, serviceId, "controlCount", 0);
			if (typeof(count) == "undefined") {
				count = 0;
			}
			var res = [];
			for (var i=0; i<count; i++) {
				res.push(get_device_state(deusDevice, serviceId, "control"+i, 0));
			}
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
		var timeMs = parseInt(get_device_state(deusDevice, serviceId, "LightsOutTime", 0));
		if (!isNaN(timeMs)) {
			time = timeMsToStr(timeMs);
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
		
		set_device_state(deusDevice, serviceId, "controlCount", controlled.length, 0);
		for (var i=0; i<controlled.length; i++) {
			set_device_state(deusDevice, serviceId, "control"+i, controlled[i], 0);
		}
	}
	
	function timeMsToStr(ms) {
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
	
	function updateTime(timeMs) {
		set_device_state(deusDevice, serviceId, "LightsOutTime", timeMs, 0);
	}
	
	checkTime = function() {
		var time = jQuery("#deusExTime").val();
		var re = new RegExp("^([0-2][0-9]):([0-6][0-9])$");
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
})();