-- L_DeusExMachinaII1.lua - Core module for DeusExMachinaII
-- Copyright 2016,2017,2019 Patrick H. Rigney, All Rights Reserved.
-- This file is part of DeusExMachinaII. For license information, see LICENSE at https://github.com/toggledbits/DeusExMachina

module("L_DeusExMachinaII1", package.seeall)

local debugMode = false

local string = require("string")

local _PLUGIN_ID = 8702 -- luacheck: ignore 211
local _PLUGIN_NAME = "DeusExMachinaII"
local _PLUGIN_VERSION = "2.10develop-19267"
local _PLUGIN_URL = "https://www.toggledbits.com/demii"
local _CONFIGVERSION = 20904 -- increment only, do not change 20 prefix

local MYSID = "urn:toggledbits-com:serviceId:DeusExMachinaII1"
local MYTYPE = "urn:schemas-toggledbits-com:device:DeusExMachinaII:1"

local SWITCH_SID  = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_SID  = "urn:upnp-org:serviceId:Dimming1"

local STATE_STANDBY = 0
local STATE_IDLE = 1
local STATE_CYCLE = 2
local STATE_SHUTDOWN = 3

local sysTaskManager = false
local systemHMD = false
local pluginDevice = -1
local isALTUI = false
local isOpenLuup = false
local devStateCache = false
local sysEvents = {}
local maxEvents = 300
local logFile = false
local actionHook
local houseModeText = { "Home", "Away", "Night", "Vacation" }

-- Forward declarations
local logToFile
-- End forwards

local function dump(t)
	if t == nil then return "nil" end
	local sep = ""
	local str = "{ "
	for k,v in pairs(t) do
		local val
		if type(v) == "table" then
			val = dump(v)
		elseif type(v) == "function" then
			val = "(function)"
		elseif type(v) == "string" then
			val = string.format("%q", v)
		else
			val = tostring(v)
		end
		str = str .. sep .. k .. "=" .. val
		sep = ", "
	end
	str = str .. " }"
	return str
end

local function L(msg, ...) -- luacheck: ignore 212
	local str
	local level = 50
	if type(msg) == "table" then
		str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg or msg[1])
		level = msg.level or level
	else
		str = _PLUGIN_NAME .. ": " .. tostring(msg)
	end
	str = string.gsub(str, "%%(%d+)", function( n )
			n = tonumber(n)
			if n < 1 or n > #arg then return "nil" end
			local val = arg[n]
			if type(val) == "table" then
				return dump(val)
			elseif type(val) == "string" then
				return string.format("%q", val)
			end
			return tostring(val)
		end
	)
	luup.log(str, level)
	if debugMode or level <= 2 then
		table.insert( sysEvents, str )
		while #sysEvents > maxEvents do table.remove( sysEvents, 1 ) end
	end
	if logFile then
		pcall( logToFile, str, level )
	end
end

local function D(msg, ...)
	if debugMode then
		L( { msg=msg,prefix=(_PLUGIN_NAME .. "(debug)::") }, ... )
	end
end

TaskManager = function( luupCallbackName )
	local callback = luupCallbackName
	local runStamp = 1
	local tickTasks = { __sched={} }
	local Task = { id=false, when=0 }

	-- Schedule a timer tick for a future (absolute) time. If the time is sooner than
	-- any currently scheduled time, the task tick is advanced; otherwise, it is
	-- ignored (as the existing task will come sooner), unless repl=true, in which
	-- case the existing task will be deferred until the provided time.
	local function scheduleTick( tkey, timeTick, flags )
		local tinfo = tickTasks[tkey]
		assert( tinfo, "Task not found" )
		assert( type(timeTick) == "number" and timeTick > 0, "Invalid schedule time" )
		flags = flags or {}
		if ( tinfo.when or 0 ) == 0 or timeTick < tinfo.when or flags.replace then
			-- Not scheduled, requested sooner than currently scheduled, or forced replacement
			tinfo.when = timeTick
		end
		-- If new tick is earlier than next plugin tick, reschedule Luup timer
		if tickTasks.__sched.when == 0 then return end -- in queue processing
		if tickTasks.__sched.when == nil or timeTick < tickTasks.__sched.when then
			tickTasks.__sched.when = timeTick
			local delay = timeTick - os.time()
			if delay < 0 then delay = 0 end
			runStamp = runStamp + 1
			luup.call_delay( callback, delay, runStamp )
		end
	end

	-- Remove tasks from queue. Should only be called from Task::close()
	local function removeTask( tkey )
		if tkey then tickTasks[ tkey ] = nil end
	end

	-- Plugin timer tick. Using the tickTasks table, we keep track of
	-- tasks that need to be run and when, and try to stay on schedule. This
	-- keeps us light on resources: typically one system timer only for any
	-- number of devices.
	local function runReadyTasks( luupCallbackArg )
		local stamp = tonumber(luupCallbackArg)
		if stamp ~= runStamp then
			-- runStamp changed, different from stamp on this call, just exit.
			return
		end

		local now = os.time()
		local nextTick = nil
		tickTasks.__sched.when = 0 -- marker (run in progress)

		-- Since the tasks can manipulate the tickTasks table (via calls to
		-- scheduleTick()), the iterator is likely to be disrupted, so make a
		-- separate list of tasks that need service (to-do list).
		local todo = {}
		for t,v in pairs(tickTasks) do
			if t ~= "__sched" and ( v.when or 0 ) ~= 0 and v.when <= now then
				table.insert( todo, v )
			end
		end

		-- Run the to-do list tasks.
		table.sort( todo, function( a, b ) return a.when < b.when end )
		for _,v in ipairs(todo) do
			v:run()
		end

		-- Things change while we work. Take another pass to find next task.
		for t,v in pairs(tickTasks) do
			if t ~= "__sched" and ( v.when or 0 ) ~= 0 then
				if nextTick == nil or v.when < nextTick then
					nextTick = v.when
				end
			end
		end

		-- Reschedule scheduler if scheduled tasks pending
		if nextTick ~= nil then
			now = os.time() -- Get the actual time now; above tasks can take a while.
			local delay = nextTick - now
			if delay < 0 then delay = 0 end
			tickTasks.__sched.when = now + delay -- that may not be nextTick
			luup.call_delay( callback, delay, luupCallbackArg )
		else
			tickTasks.__sched.when = nil -- remove when to signal no timer running
		end
	end

	function Task:schedule( when, flags )
		assert(self.id, "Can't reschedule() a closed task")
		scheduleTick( self.id, when, flags )
		return self
	end

	function Task:delay( delay, flags )
		assert(self.id, "Can't delay() a closed task")
		scheduleTick( self.id, os.time()+delay, flags )
		return self
	end

	function Task:suspend()
		self.when = 0
		return self
	end

	function Task:run()
		assert(self.id, "Can't run() a closed task")
		self.when = 0
		local success, err = pcall( self.func, self, unpack( self.args or {} ) )
		if not success then L({level=1, msg="Task:run() task %1 failed: %2"}, self, err) end
		return self
	end

	function Task:close()
		removeTask( self.id )
		self.id = nil
		self.when = 0
		self.args = nil
		self.func = nil
		return self
	end

	function Task:new( id, owner, tickFunction, args, desc )
		assert( id == nil or tickTasks[tostring(id)] == nil,
			"Task already exists with id "..tostring(id)..": "..tostring(tickTasks[tostring(id)]) )
		assert( type(owner) == "number" )
		assert( type(tickFunction) == "function" )

		local obj = { when=0, owner=owner, func=tickFunction, name=desc or tostring(owner), args=args }
		obj.id = tostring( id or obj )
		setmetatable(obj, self)
		self.__index = self

		tickTasks[ obj.id ] = obj
		return obj
	end

	local function getOwnerTasks( owner )
		local res = {}
		for k,v in pairs( tickTasks ) do
			if owner == nil or v.owner == owner then
				table.insert( res, k )
			end
		end
		return res
	end

	local function getTask( id )
		return tickTasks[tostring(id)]
	end

	return {
		runReadyTasks = runReadyTasks,
		getOwnerTasks = getOwnerTasks,
		getTask = getTask,
		Task = Task,
		_tt = tickTasks
	}
end

local function getInstallPath()
	if not installPath then
		installPath = "/etc/cmh-ludl/" -- until we know otherwise
		if isOpenLuup then
			local loader = require "openLuup.loader"
			if loader.find_file then
				installPath = loader.find_file( "L_DeusExMachinaII1.lua" ):gsub( "L_DeusExMachinaII1.lua$", "" )
			end
		end
	end
	return installPath
end

local function checkVersion(dev)
	local ui7Check = luup.variable_get(MYSID, "UI7Check", dev) or ""
	if isOpenLuup or ( luup.version_branch == 1 and luup.version_major >= 7 ) then
		if ui7Check == "" then
			-- One-time init for UI7 or better
			luup.variable_set(MYSID, "UI7Check", "true", dev)
			luup.attr_set("device_json", "D_DeusExMachinaII1_UI7.json", dev)
			luup.reload()
		end
	elseif luup.version_branch == 1 and luup.version_major < 5 then
		luup.set_failure( 1, dev )
		error("Unsupported firmware " .. luup.version)
	else
		if ui7Check == "" then
			-- One-time init for UI5/6
			luup.variable_set(MYSID, "UI7Check", "false", dev)
			luup.attr_set("device_json", "D_DeusExMachinaII1.json", dev)
			luup.reload()
		end
	end
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, sid )
	dev = dev or pluginDevice
	sid = sid or MYSID
	local s = luup.variable_get(sid, name, dev) or ""
	if s == "" then return dflt end
	return tonumber(s) or dflt
end

-- Initialize a variable if it does not already exist.
local function initVar( sid, name, dflt, dev )
	dev = dev or pluginDevice
	local currVal = luup.variable_get( sid, name, dev )
	if currVal == nil then
		luup.variable_set( sid, name, tostring(dflt), dev )
		return tostring(dflt)
	end
	return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
	dev = dev or pluginDevice
	val = (val == nil) and "" or tostring(val)
	local s = luup.variable_get( sid, name, dev ) or ""
	if s ~= val then
		luup.variable_set( sid, name, val, dev )
	end
	return s
end

-- Delete a variable
local function deleteVar( name, devid, sid )
	luup.variable_set( sid or MYSID, name, nil, devid or pluginDevice )
end

local function setMessage(s, dev)
	setVar(MYSID, "Message", s or "", dev or pluginDevice)
end

-- Log message to log file.
logToFile = function(str, level)
	lfn = getInstallPath() .. "DeusActivity.log"
	if logFile == false then
		logFile = io.open(lfn, "a")
		-- Yes, we leave nil if it can't be opened, and therefore don't
		-- keep trying to open as a result. By design.
	end
	if logFile then
		local maxsizek = getVarNumeric("MaxLogSize", 0)
		if maxsizek <= 0 then
			-- We should not be open now (runtime change, no reload needed)
			logFile:close()
			logFile = false
			return
		end
		if logFile:seek("end") >= (1024*maxsizek) then
			logFile:close()
			os.execute("pluto-lzo c '" .. lfn .. "' '" .. lfn .. ".lzo'")
			logFile = io.open(lfn, "w")
		end
		level = level or 50
		logFile:write(string.format("%02d %s %s\n", level, os.date("%x.%X"), str))
		logFile:flush()
	end
end

-- Shortcut function to return state of SwitchPower1 Status variable
local function isEnabled()
	local s = luup.variable_get(SWITCH_SID, "Target", pluginDevice) or "0"
	D("isEnabled() Target=%1, pluginDevice=%2", s, pluginDevice)
	return s ~= "0"
end

local function isActiveHouseMode( currentMode )
	-- Fetch our mask bits that tell us what modes we operate in. If 0, we're not checking house mode.
	local modebits = getVarNumeric("HouseModes", 0)
	if modebits ~= 0 then
		-- Get the current house mode.
		currentMode = currentMode or tonumber(luup.attr_get("Mode", 0) or 1) or 1

		-- Check to see if house mode bits are non-zero, and if so, apply current mode as mask.
		-- If bit is set (current mode is in the bitset), we can run, otherwise skip.
		-- Get the current house mode (1=Home,2=Away,3=Night,4=Vacation) and mode into bit position.
		currentMode = math.pow(2, currentMode)
		if (math.floor(modebits / currentMode) % 2) == 0 then
			D('isActiveHouseMode(): Current mode bit %1 not set in %2', string.format("0x%x", currentMode), string.format("0x%x", modebits))
			return false -- not active in this mode
		else
			D('isActiveHouseMode(): Current mode bit %1 SET in %2', string.format("0x%x", currentMode), string.format("0x%x", modebits))
		end
	end
	return true -- default is we're active in the current house mode
end

-- Get a random delay from two state variables. Error check.
local function getRandomDelay(minStateName,maxStateName,defMin,defMax)
	defMin = defMin or 300
	defMax = defMax or 1800
	local mind = getVarNumeric(minStateName, defMin)
	if mind < 1 then mind = 1 elseif mind > 7200 then mind = 7200 end
	local maxd = getVarNumeric(maxStateName, defMax)
	if maxd < 1 then maxd = 1 elseif maxd > 7200 then maxd = 7200 end
	if maxd <= mind then return mind end
	return math.random( mind, maxd )
end

-- Get sunset time in minutes since midnight. May override for test mode value.
local function getSunset()
	-- Figure out our sunset time. Note that if we make this inquiry after sunset, MiOS
	-- returns the time of tomorrow's sunset. But, that's not different enough from today's
	-- that it really matters to us, so go with it.
	local sunset = luup.sunset()
	local testing = getVarNumeric("TestMode", 0)
	if (testing ~= 0) then
		local m = getVarNumeric( "TestSunset", nil ) -- units are minutes since midnight
		if (m ~= nil) then
			-- Sub in our test sunset time
			local t = os.date('*t', sunset)
			t['hour'] = math.floor(m / 60)
			t['min'] = math.floor(m % 60)
			t['sec'] = 0
			sunset = os.time(t)
			D('getSunset(): testing mode sunset override %1, as timeval is %2', m, sunset)
		end
	end
	if (sunset <= os.time()) then sunset = sunset + 86400 end
	return sunset
end

-- Return start time in seconds. Could be configured, could be sunset.
local function startTime(dev)
	local st = luup.variable_get(MYSID, "StartTime", dev) or ""
	D("startTime() start time=%1",st)
	if string.match(st, "^%s*$") then
		st = getSunset()
		local tt = os.date("*t", st)
		return st, string.format("sunset (%02d:%02d)", tt.hour, tt.min)
	else
		local tt = os.date("*t")
		tt.hour = math.floor(st/60)
		tt.min = st % 60
		tt.sec = 0
		local ts = os.time(tt)
		D("startTime() tt=%1, ts=%2", tt, ts)
		return ts, string.format("%02d:%02d", tt.hour, tt.min)
	end
end

-- DEM cycles lights between start and lights-out. This function returns 0 if
-- the current time is between start and lights-out; otherwise 1. Note that all
-- times are reduced to minutes-since-midnight.
local function isBedtime()
	local testing = getVarNumeric("TestMode", 0)
	if testing ~= 0 then
		D('isBedtime(): TestMode is on')
		debugMode = true
	end

	-- Establish the lights-out time
	local bedtime = 1439 -- that's 23:59 in minutes since midnight (default)
	local bedtime_tmp = luup.variable_get(MYSID, "LightsOut", pluginDevice)
	if bedtime_tmp ~= nil then
		bedtime_tmp = tonumber(bedtime_tmp,10)
		if (bedtime_tmp >= 0 and bedtime_tmp < 1440) then bedtime = bedtime_tmp end
	end

	-- Figure out our start time in MSM
	local start = os.date('*t', startTime(pluginDevice))
	start = start.hour*60 + start.min

	-- And the current time.
	local dt = os.date('*t')
	local tNow = dt.hour*60 + dt.min

	-- Figure out if we're betweeen sunset and lightout (ret=0) or not (ret=1)
	D('isBedtime(): times (mins since midnight) are now=%1, start=%2, bedtime=%3', tNow, start, bedtime)
	local ret = 1 -- guilty until proven innocent
	if (bedtime > start) then
		-- Case 1: bedtime is after start (i.e. between start and midnight)
		if (tNow >= start and tNow < bedtime) then
			ret = 0
		end
	elseif bedtime == start then
		-- Case 3: explicitly handle case of start/lightsout being equal: DEMII always runs.
		-- This facilitates scene-based control of DEMII via enable/disable, making sensor
		-- triggering (GitHub issue 21) and multiple cycle periods (GitHub issue 18) possible.
		ret = 0
	else
		-- Case 2: bedtime is after midnight
		if (tNow >= start or tNow < bedtime) then
			ret = 0
		end
	end
	D("isBedtime(): returning %1", ret)
	return ret
end

local function split( str, sep )
	if sep == nil then sep = "," end
	local arr = {}
	if #str == 0 then return arr, 0 end
	local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
	table.insert( arr, rest )
	return arr, #arr
end

local function getDeviceState()
	if not devStateCache then
		local json = require "dkjson"
		local d = luup.variable_get(MYSID, "DeviceState", pluginDevice) or "{}"
		devStateCache = json.decode( d ) or {}
	end
	return devStateCache
end

local function clearDeviceState()
	D("clearDeviceState()")
	luup.variable_set(MYSID, "DeviceState", "{}", pluginDevice)
	devStateCache = {}
end

local function updateDeviceState( spec, isOn, expire )
	D("updateDeviceState(%1,%2,%3)", spec, isOn, expire )
	spec = tostring(spec)
	local devState = getDeviceState()
	if devState[spec] == nil then devState[spec] = {} end
	if isOn then
		devState[spec].state = 1
		devState[spec].onTime = os.time()
		devState[spec].expire = expire
	else
		devState[spec].state = 0
		devState[spec].offTime = os.time()
		devState[spec].expire = nil
	end
	local json = require "dkjson"
	luup.variable_set(MYSID, "DeviceState", json.encode( devState ), pluginDevice)
	return devState
end

-- Return true if a specified scene has been run.
local function isSceneOn(spec)
	local devState = getDeviceState()
	return (devState[spec] or {}).state == 1
end

-- Mark or unmark a scene as having been run. Use devState.
local function updateSceneState(spec, isOn)
	updateDeviceState( spec, isOn, nil )
end

-- Find scene by name
local function findScene(name, dev)
	D("findScene(%1,%2)", name, dev)
	name = name:lower()
	for k,v in ipairs( luup.scenes or {} ) do
		if v.description:lower() == name then return k, v end
	end
	return nil
end

-- Run "final" scene, if defined. This scene is run after all other targets have been
-- turned off.
local function runFinalScene(dev)
	D("runFinalScene(%1)", dev)
	local scene  = getVarNumeric("FinalScene", nil)
	if (scene ~= nil and luup.scenes[scene] ~= nil) then
		D("runFinalScene(): running final scene %1", scene)
		-- Hackish. Check scene name to see if there's a house-mode variant. For ex.,
		-- if the final scene is named "DeusEnd" or "DeusEndHome", look for scenes
		-- DeusEndAway, DeusEndVacation, DeusEndNight.
		local houseModes = getVarNumeric("HouseModes", 0, pluginDevice)
		if houseModes ~= 0 then
			local fname = (luup.scenes[scene].description or ""):lower()
			fname = fname:gsub("home$","")
			local mode = getVarNumeric("LastHouseMode", 1, pluginDevice)
			if mode >= 1 and mode <= 4 then
				local modeName = fname .. ({[1]="home",[2]="away",[3]="night",[4]="vacation"})[mode]
				local s = findScene( modeName, pluginDevice )
				if s ~= nil then
					L("Found final scene %1 for (last) house mode %2", luup.scenes[s].description, mode)
					scene = s
				end
			end
		end
		luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=scene }, 0)
	end
end

-- Get the list of targets from our device state, parse to table of targets.
local function getTargetList()
	local s = luup.variable_get(MYSID, "Devices", pluginDevice) or ""
	return split(s)
end

local function arrayIndexOf( ar, elem )
	for i,d in ipairs( ar or {} ) do
		if d == elem then return i end
	end
	return false
end

-- Remove a target from the target list. Used when the target no longer exists. Linear, poor, but short list and rarely used.
local function removeTarget(target, tlist)
	if tlist == nil then tlist = getTargetList() end
	target = tostring(target)
	local devState = getDeviceState()
	devState[target] = nil
	local ix = arrayIndexOf( tlist, target )
	if ix then
		table.remove( tlist, ix )
		luup.variable_set(MYSID, "Devices", table.concat(tlist, ","), pluginDevice)
		return true
	end
	return false
end

-- Light on or off? Returns boolean
local function isDeviceOn(targetid)
	local first = string.upper(string.sub(targetid, 1, 1))
	if first == "S" then
		D("isDeviceOn(): handling scene spec %1", targetid)
		return isSceneOn( targetid )
	end

	-- Handle as switch or dimmer. Forced agreement between cached device state
	-- and actual device state.
	D("isDeviceOn(): handling target spec %1", targetid)
	local devState = getDeviceState()
	local r = tonumber( string.match(targetid, '^%d+') or -1 )
	local val = "0"
	if luup.devices[r] ~= nil then
		local dst = devState[tostring(targetid)] or {}
		if dst then return dst.state == 1 end
		D("isDeviceOn() dev %1 state not cached, fetching", r)
		if luup.device_supports_service(SWITCH_SID, r) then
			val = luup.variable_get(SWITCH_SID, "Status", r) or "0"
		end
		D("isDeviceOn(): current device %1 status is %2", r, val)
		updateDeviceState( targetid, val ~= "0", nil )
	else
		D("isDeviceOn(): target spec %1, device %2 not found in luup.devices", targetid, r)
		removeTarget(targetid)
		return nil
	end
	return val ~= "0"
end

-- Call the action hook, if specified
local function doActionHook( target, state )
	local s = getVarNumeric( "PreactionScene", 0 )
	if s > 0 then
		local ra,rb,rj,rd = luup.call_action( "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=s }, 0 )
		D("runScene() scene hand-off to Luup returns %1,%2,%3,%4", ra, rb, rj, rd)
		if ra ~= 0 then
			L({level=2,msg="invocation of preaction scene %1 failed: %2"}, s, rb)
		elseif rj > 0 then
			L({level=2,msg="WARNING: Luup started the preaction scene as a job! Race condition probable!"}, s )
		end
	end
	if actionHook == nil then
		local f,err = loadfile( getInstallPath() .. "DEMIIAction.lua" )
		if err then
			L({level=2,msg="DEMIIAction.lua can't be loaded: %1"}, err)
			actionHook = false -- prevent further load attempts
		else
			-- Call the code, which must return a function
			--[[ Sample DEMIIAction.lua:
					return function( target, state )
						luup.log("DEMII action hook running, I'm about to turn " .. tostring(target) .. ( state and " on" or " off"))
					end
			--]]
			local status
			status,actionHook = pcall( f )
			if not status or type(actionHook) ~= "function" then
				L({level=2,msg="DEMIIAction.lua: %1"}, status and "returned value is not a function" or actionHook)
				actionHook = false -- prevent further load attempts
			end
		end
	end
	if actionHook then
		D("doActionHook() running %1(%2,%3)", actionHook, target, state)
		local status,err = pcall( actionHook, target, state )
		if not status then
			L({level=2,msg="DEMIIAction.lua pre-action hook failed: %1"}, err)
		end
	end
end

-- Control target. Target is a string, expected to be a pure integer (in which case the target is assumed to be a switch or dimmer),
-- or a string in the form Sxx:yy, in which case xx is an "on" scene to run, and yy is an "off" scene to run.
local function targetControl(targetid, turnOn)
	D("targetControl(): targetid=%1, turnOn=%2", targetid, turnOn)
	local first = string.upper(string.sub(targetid, 1, 1))
	if first == "S" then
		D("targetControl(): handling as scene spec %1", targetid)
		local i, _, onScene, offScene = string.find(string.sub(targetid, 2), "(%d+)-(%d+)")
		if i == nil then
			D("DeusExMachina:targetControl(): malformed scene spec=" .. tostring(targetid))
			return
		end
		onScene = tonumber(onScene, 10)
		offScene = tonumber(offScene, 10)
		if luup.scenes[onScene] == nil or luup.scenes[offScene] == nil then
			-- Both on scene and off scene must exist (defensive).
			D("targetControl(): one or both of the scenes in " .. tostring(targetid) .. " not found in luup.scenes!")
			removeTarget(targetid)
			return
		end
		D("targetControl(): on scene is %1, off scene is %2", onScene, offScene)
		local targetScene
		if turnOn then targetScene = onScene else targetScene = offScene end
		doActionHook( targetid, true )
		luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=targetScene }, 0)
		updateSceneState(targetid, turnOn)
	else
		local lvl = 100
		local maxOnTime = false
		local devid = targetid -- string for now
		-- Parse time limit if specified (must be end of string/spec)
		local m = string.find(devid, '<')
		if m ~= nil then
			maxOnTime = string.sub(devid, m+1)
			devid = string.sub(devid, 1, m-1)
		end
		-- Parse the level if this is a dimming target spec
		local k, _, j, l = string.find(devid, "(%d+)=(%d+)")
		if k then
			devid = j
			lvl = tonumber( l, 10 ) or 100
		end
		devid = tonumber(devid, 10) or -1 -- convert to number
		-- Level for all types is 0 if turning device off
		if not turnOn then lvl = 0 end
		if luup.devices[devid] == nil then
			-- Device doesn't exist (user deleted, etc.). Remove from Devices state variable.
			D("targetControl(): device %1 not found in luup.devices, targetid=", devid, targetid)
			removeTarget(targetid)
			return
		end
		local category = tonumber( luup.attr_get( 'category_num', devid ) ) or -1
		doActionHook( devid, turnOn )
		if luup.device_supports_service("urn:upnp-org:serviceId:VSwitch1", devid) and getVarNumeric( "UseOldVSwitch", 0 ) ~= 0 then
			lvl = turnOn and "1" or "0"
			D("targetControl(): handling %1 (%3) as VSwitch, set target to %2", devid, lvl, luup.devices[devid].description)
			luup.call_action("urn:upnp-org:serviceId:VSwitch1", "SetTarget", { newTargetValue=tostring(lvl) }, devid)
		elseif turnOn and category == 2 then
			-- Handle as Dimming1 for power ON only.
			D("targetControl(): handling %1 (%3) as generic dimmmer, set load level to %2", devid, lvl, luup.devices[devid].description)
			luup.call_action(DIMMER_SID, "SetLoadLevelTarget", { newLoadlevelTarget=tostring(lvl) }, devid) -- note odd case inconsistency in word "level"
		else
			-- Everything else gets handled as a switch.
			if not luup.device_supports_service("urn:upnp-org:serviceId:SwitchPower1", devid) then
				L({level=2,msg="Device %1 (#%2) type unrecognized, being handled as binary light."}, luup.devices[devid], devid)
			end
			lvl = turnOn and "1" or "0"
			D("targetControl(): handling %1 (%3) as generic switch, set target to %2", devid, lvl, luup.devices[devid].description)
			luup.call_action(SWITCH_SID, "SetTarget", { newTargetValue=tostring(lvl) }, devid)
		end
		local expire = nil
		if turnOn and maxOnTime then
			maxOnTime = tonumber( maxOnTime ) * 60 -- now seconds
			expire = os.time() + maxOnTime
		end
		updateDeviceState(targetid, turnOn, expire)
		return maxOnTime
	end
end

-- Get list of targets that are on
local function getTargetsOn()
	local on = {}
	local devs,maxl = getTargetList()
	if maxl > 0 then
		for i = 1,maxl do
			if isDeviceOn( devs[i] ) == true then -- skip nil
				table.insert(on, devs[i])
			end
		end
	end
	return on, #on
end

-- Turn off a light, if any is on. Returns 1 if there are more lights to turn off; otherwise 0.
local function turnOffLight(on)
	local n
	if on == nil then
		on, n = getTargetsOn()
	else
		n = #on
	end
	if n > 0 then
		local i = math.random(1, n)
		local target = on[i]
		targetControl(target, false)
		table.remove(on, i)
		n = n - 1
		D("turnOffLight(): turned %1 OFF, still %2 targets on", target, n)
	end
	return (n > 0), on, n
end

-- See if there's a limited-time device that needs to be turned off.
local function turnOffLimited()
	local devState = getDeviceState()
	local res = false
	local nextLimited = false
	local now = os.time()
	for targetid,info in pairs( devState or {} ) do
		if info.expire ~= nil then
			if info.expire <= now then
				L("Cycle: turn %1 off (time limit expired)", targetid)
				targetControl(targetid, false)
				res = true
			elseif ( not nextLimited ) or info.expire < nextLimited then
				nextLimited = info.expire
			end
		end
	end
	return res, nextLimited
end

-- Turn off all lights as fast as we can. Transition through SHUTDOWN state during,
-- in case user has any triggers connected to that state. The caller must immediately
-- set the next state when this function returns (expected would be STANDBY or IDLE).
local function clearLights()
	D("clearLights()")
	local devs, count
	devs, count = getTargetList()
	setVar(MYSID, "State", STATE_SHUTDOWN, pluginDevice)
	while count > 0 do
		targetControl(devs[count], false)
		count = count - 1
	end
	clearDeviceState()
	runFinalScene()
end

-- Set HMT ModeSetting
local function setHMTModeSetting( hmtdev )
	if not hmtdev then return end
	local chm = luup.attr_get( 'Mode', 0 ) or "1"
	local armed = getVarNumeric( "Armed", 0, hmtdev, "urn:micasaverde-com:serviceId:SecuritySensor1" ) ~= 0
	local s = {}
	for ix=1,4 do
		table.insert( s, string.format( "%d:%s", ix, ( tostring(ix) == chm ) and ( armed and "A" or "" ) or ( armed and "" or "A" ) ) )
	end
	s = table.concat( s, ";" )
	D("setHMTModeSetting(%4) HM=%1 armed=%2; new ModeSetting=%3", chm, armed, s, hmtdev)
	luup.variable_set( "urn:micasaverde-com:serviceId:HaDevice1", "ModeSetting", s, hmtdev )
end

-- Get the house mode tracker. If it doesn't exist, create it (child device).
-- No HMT on openLuup because it doesn't have native device file to support it.
local function getHouseModeTracker( createit, pdev )
	pdev = pdev or pluginDevice
	if not isOpenLuup then
		for k,v in pairs( luup.devices ) do
			if v.device_num_parent == pdev and v.id == "hmt" then
				return k, v
			end
		end
		-- Didn't find it. At this point, we have a list of children.
		if createit then
			-- Didn't find it. Need to create a new child device for it. Sigh.
			L{level=2,msg="Did not find house mode tracker; creating. This will cause a Luup reload."}
			local ptr = luup.chdev.start( pdev )
			setMessage( "Message", "Adding house mode tracker, please wait..." )
			--[[
			for k,v in pairs( luup.devices ) do
				if v.device_num_parent == pdev then
					local df = dfMap[ v.device_type ]
					D("getHouseModeTracker() appending existing device %1 (%2)", v.id, v.description)
					luup.chdev.append( pdev, ptr, v.id, v.description, "", df.device_file, "", "", false )
				end
			end
			--]]
			D("getHouseModeTracker() creating hmt child; final step before reload.")
			luup.chdev.append( pdev, ptr, "hmt", "DeusExMachinaII HMT", "", "D_DoorSensor1.xml", "", "", false )
			luup.chdev.sync( pdev, ptr )
			-- Should cause reload immediately. Drop through.
		end
	end
	return false
end

local function startCycling(dev)
	D("startCycling(%1)", dev)
	clearDeviceState()
	setVar(MYSID, "State", STATE_CYCLE, dev)
	setVar(MYSID, "NextStep", "0", dev)
	-- Give externals a chance to react to state change
	sysTaskManager.getTask( "cycler" ):delay( 5 )
end

local function stopCycling( dev )
	D("stopCycling(%1)", dev)
	local currState = getVarNumeric( "State", STATE_STANDBY, dev )
	if currState == STATE_CYCLE or currState == STATE_SHUTDOWN then
		sysTaskManager.getTask( "cycler" ):suspend()
		if getVarNumeric("LeaveLightsOn", 0) == 0 then
			clearLights()
		else
			runFinalScene( dev ) -- always run final scene
		end
		setVar(MYSID, "State", STATE_IDLE, pluginDevice)
		setVar(MYSID, "NextStep", "0", dev)
		setMessage("Idle")
	end
	clearDeviceState()
end

-- runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place. For us, that means looking to see if an older version of Deus is still
-- installed, and copying its config into our new config. Then disable the old Deus.
local function runOnce()
	local s = getVarNumeric("Version", 0)
	if s == 0 then
		D("runOnce(): updating config for first-time initialization")
		initVar( MYSID, "Enabled", 0, pluginDevice )
		initVar( MYSID, "State", STATE_STANDBY, pluginDevice )
		initVar( MYSID, "AutoTiming", "1", pluginDevice )
		initVar( MYSID, "StartTime", "", pluginDevice )
		initVar( MYSID, "LightsOut", 1439, pluginDevice )
		initVar( MYSID, "MinTargetsOn", 1, pluginDevice )
		initVar( MYSID, "MaxTargetsOn", 0, pluginDevice )
		initVar( MYSID, "LeaveLightsOn", 0, pluginDevice )
		initVar( MYSID, "MaxLogSize", 64, pluginDevice )
		initVar( MYSID, "Active", "0", pluginDevice )
		initVar( MYSID, "LastHouseMode", "1", pluginDevice )
		initVar( MYSID, "NextStep", "0", pluginDevice )
		initVar( MYSID, "DebugMode", 0, pluginDevice )
		initVar( MYSID, "MinCycleDelay", "", pluginDevice )
		initVar( MYSID, "MaxCycleDelay", "", pluginDevice )
		initVar( MYSID, "MinOffDelay", "", pluginDevice )
		initVar( MYSID, "MaxOffDelay", "", pluginDevice )
		initVar( SWITCH_SID, "Target", 0, pluginDevice )
		initVar( SWITCH_SID, "Status", 0, pluginDevice )
		initVar( MYSID, "Version", _CONFIGVERSION, pluginDevice )
		return
	end
	-- Handle upgrades from prior versions.
	if s < 20300 then
		-- v2.3: LightsOutTime (in milliseconds) deprecated, now using LightsOut (in minutes since midnight)
		D("runOnce(): updating config, version %1 < 20300", s)
		local t = luup.variable_get(MYSID, "LightsOut", pluginDevice)
		if t == nil then
			t = getVarNumeric("LightsOutTime") -- get pre-2.3 variable
			if t == nil then
				luup.variable_set(MYSID, "LightsOut", 1439, pluginDevice) -- default 23:59
			else
				luup.variable_set(MYSID, "LightsOut", ( tonumber(t) or 86340000 )  / 60000, pluginDevice) -- conv ms to minutes
			end
		end
		deleteVar("LightsOutTime", pluginDevice)
	end
	if s < 20400 then
		-- v2.4: SwitchPower1 variables added. Follow previous plugin state in case of auto-update.
		D("runOnce(): updating config, version %1 < 20400", 2)
		initVar(MYSID, "MaxTargetsOn", 0, pluginDevice)
		local e = getVarNumeric("Enabled", 0)
		initVar(SWITCH_SID, "Target", e, pluginDevice)
		initVar(SWITCH_SID, "Status", e, pluginDevice)
	end
	if s < 20500 then
		-- v2.5: Added StartTime and LeaveLightsOn
		D("runOnce(): updating config, version %1 < 20500", s)
		initVar(MYSID, "StartTime", "", pluginDevice)
		initVar(MYSID, "LeaveLightsOn", 0, pluginDevice)
	end
	if s < 20800 then
		-- v2.8 Added Active and AutoTiming
		D("runOnce(): updating config, version %1 < 20800", s)
		initVar(MYSID, "Active", "0", pluginDevice)
		initVar(MYSID, "AutoTiming", "1", pluginDevice)
		initVar(MYSID, "LastHouseMode", "1", pluginDevice)
		initVar(MYSID, "NextStep", "0", pluginDevice)
	end
	if s < 20900 then
		initVar( MYSID, "MinTargetsOn", 1, pluginDevice )
		initVar( MYSID, "DebugMode", 0, pluginDevice )
	end
	if s < 20903 then
		initVar( MYSID, "MinCycleDelay", "", pluginDevice )
		initVar( MYSID, "MaxCycleDelay", "", pluginDevice )
		initVar( MYSID, "MinOffDelay", "", pluginDevice )
		initVar( MYSID, "MaxOffDelay", "", pluginDevice )
	end
	if s < 20904 then
		initVar( MYSID, "MaxLogSize", "64", pluginDevice )
	end

	-- Update version state last.
	setVar(MYSID, "Version", _CONFIGVERSION, pluginDevice)
end

-- Return the plugin version string
function getVersion()
	return _PLUGIN_VERSION, _CONFIGVERSION
end

-- Enable DEM by setting a new cycle stamp and scheduling our first cycle step.
function deusEnable(dev)
	L("Enabling")

	setMessage("Enabling...", dev)

	setVar(SWITCH_SID, "Target", "1", dev)
	-- Old Enabled variable follows SwitchPower1's Target
	setVar(MYSID, "Enabled", "1", dev)
	setVar(MYSID, "State", STATE_IDLE, dev)
	setVar(MYSID, "NextStep", 0, dev)

	-- Resume house mode poller
	if systemHMD then
		setHMTModeSetting( systemHMD )
		local hmp = sysTaskManager.getTask( "hmpoll" )
		if hmp then hmp:delay( 15 ) end
	end

	-- Kick master task.
	sysTaskManager.getTask( "master" ):delay( 0 )

	-- SwitchPower1 status now on, we are running.
	setVar(SWITCH_SID, "Status", "1", dev)
end

-- Disable DEM and go to standby state. If we are currently cycling (as opposed to idle/waiting for sunset),
-- turn off any controlled lights that are on.
function deusDisable(dev)
	L("Disabling")
	-- assert(dev == pluginDevice)

	setVar(SWITCH_SID, "Target", "0", dev)
	setVar(MYSID, "Enabled", "0", dev)

	setMessage("Disabling...", dev)

	stopCycling(dev)

	setVar(MYSID, "State", STATE_STANDBY, dev)
	setVar(SWITCH_SID, "Status", "0", dev)

	setMessage("Disabled")
end

function actionActivate( dev, newState )
	D("actionActivate(%1,%2)", dev, newState)

	if not isEnabled( dev ) then
		L("Activate (%1) action request ignored; disabled.", newState)
		return
	end

	-- Force reload of the action hook every time (even if this call doesn't succeed)
	actionHook = nil

	local timing = getVarNumeric( "AutoTiming", 1, dev )
	if timing == 0 then
		-- Manual timing, so this action will (can) work...
		local currState = getVarNumeric("State", STATE_STANDBY, dev)
		if newState then
			-- Activate.
			L("Manual activation action.")
			local n = getVarNumeric( "NextStep", 0 )
			if currState == STATE_IDLE or n == 0 then
				setMessage("Activating,,,")
				startCycling(dev)
			elseif currState == STATE_SHUTDOWN then
				setMessage("Resuming cycling...")
				setVar(MYSID, "State", STATE_CYCLE, dev )
			else
				setMessage("Activated; next cycle " .. os.date("%X", n))
				L("Ignored request for manual activation, already running (%1).", currState)
			end
		else
			if currState == STATE_CYCLE then
				L("Manual deactivation action.")
				setVar(MYSID, "State", STATE_SHUTDOWN, dev)
				setVar(MYSID, "NextStep", 0, dev)
				setMessage("Deactivating...")
				sysTaskManager.getTask( "cycler" ):delay( 0 ) -- kick cycler
			else
				L("Ignored request to deactivate, already shut/shutting down")
			end
		end
	else
		local which = newState and "activate" or "deactivate"
		L("Action request to %1 ignored, unable when automatic timing is enabled.", which)
		setMessage("AutoTiming on; can't " .. which)
	end
end

function setTrace(dev, newTraceState)
	D("setTrace(%1,%2)", dev, newTraceState)
	debugMode = newTraceState
	local n
	if newTraceState then n=1 else n=0 end
	setVar(MYSID, "DebugMode", n, dev)
	setVar(MYSID, "TraceMode", n, dev)
	D("setTrace() set state to %1 by action", newTraceState)
end

local function runMasterTask( task, dev )
	D("runMasterTask(%1,%2)",task,dev)
	if isEnabled() then
		local currState = getVarNumeric("State", STATE_STANDBY, dev)

		-- Get going...
		local isAutoTiming = getVarNumeric( "AutoTiming", 1, dev ) ~= 0
		if not isAutoTiming then
			-- Set message for idle state. Other states handled in runCyclerTask.
			D("runMasterTask() auto-timing off; current state is %1", currState)
			if currState == STATE_IDLE then
				setMessage("Waiting for activation")
			else
				local nextStep = getVarNumeric( "NextStep", 0, dev )
				setMessage("Cycling; next at " .. os.date("%X", nextStep))
			end
			return -- don't reschedule master task
		end

		-- Auto-timing check.
		local sunset = getSunset()
		local nextStart, startWord = startTime( dev )
		local lightsOut = getVarNumeric( "LightsOut", 1439, dev )
		if debugMode then
			D("runMasterTask(): in state %1, lightsout=%2, sunset=%3, nextStart=%5, os.time=%4", currState,
				lightsOut, sunset, os.time(), nextStart)
			D("runMasterTask(): luup variables longitude=%1, latitude=%2, timezone=%3, city=%4, sunset=%5, version=%6",
				luup.longitude, luup.latitude, luup.timezone, luup.city, luup.sunset(), luup.version)
		end

		local inActiveTimePeriod = isBedtime() == 0
		local mode = tonumber( luup.attr_get( "Mode", 0 ) ) or 1
		local inActiveHouseMode = isActiveHouseMode( mode )
		-- We're auto-timing. We may need to do something...
		if inActiveTimePeriod then
			D("runMasterTask(): in active time period")
			if inActiveHouseMode then
				D("runMasterTask(): in active house mode, currState=%1", currState)
				-- Right time, right house mode.
				if currState == STATE_IDLE then
					-- Get rolling!
					L("Auto-start! Launching cycler...")
					setMessage("Starting...")
					startCycling(dev)
				elseif currState == STATE_CYCLE or currState == STATE_SHUTDOWN then
					local t = sysTaskManager.getTask( 'cycler' )
					D("runMasterTick(): cycling in valid time and house mode, next at %1", t.when)
					if t.when == 0 then
						L{level=2, msg="Cycler hard start"}
						t:delay( 0 )
					end
				end
				return task:delay( 60 )
			else
				-- Right time, wrong house mode.
				D("runMasterTask(): not active house mode, currState=%1", currState)
				if currState == STATE_CYCLE or currState == STATE_SHUTDOWN then
					L("Stopping; inactive house mode")
					setMessage("Stopping; inactive house mode")
					stopCycling( dev )
				end
				setMessage( "Inactive in " .. ( houseModeText[mode] or tostring(mode) ) .. " mode" )
				if nextStart <= os.time() then nextStart = nextStart + 86400 end
				return task:schedule( nextStart ) -- default timing
			end
		else
			D("runMasterTask(): not active time period")
			if inActiveHouseMode then
				D("runMasterTask(): in active house mode for inactive period, currState=%1", currState)
				-- Wrong time, right house mode.
				if currState == STATE_CYCLE then
					L("Lights-out (auto timing), transitioning to shut-off cycles...")
					setMessage("Starting lights-out...")
					setVar(MYSID, "State", STATE_SHUTDOWN, dev)
					return task:delay( 60 )
				elseif currState == STATE_SHUTDOWN then
					-- Keep working.
					return task:delay( 60 )
				end
			else
				-- Wrong time, wrong house mode.
				D("runMasterTask(): inactive house mode, inactive time period, currState=%1", currState)
				if currState == STATE_CYCLE or currState == STATE_SHUTDOWN then
					L("Stopping; inactive house mode")
					setMessage("Stopping; inactive house mode")
					stopCycling( dev )
				end
			end
			L("Waiting for " .. startWord)
			setMessage("Waiting for " .. startWord)
			if nextStart <= os.time() then nextStart = nextStart + 86400 end
			return task:schedule( nextStart ) -- default timing
		end
	else
		D("runMasterTask() disabled")
		setMessage("Disabled")
		task:suspend()
	end
end

-- Run a cycle. If we're in "bedtime" (i.e. not between our cycle period between sunset and stop),
-- then we'll shut off any lights we've turned on and queue another run for the next sunset. Otherwise,
-- we'll toggled one of our controlled lights, and queue (random delay, but soon) for another cycle.
-- The shutdown of lights also occurs randomly, but can (through device state/config) have different
-- delays, so the lights going off looks more "natural" (i.e. not all at once just slamming off).
local function runCyclerTask( task, dev )
	D("runCyclerTask(%1,%2)", task, dev )

	local now = os.time()
	local currentState = getVarNumeric("State", STATE_SHUTDOWN, pluginDevice)
	if currentState ~= STATE_CYCLE and currentState ~= STATE_SHUTDOWN then
		L({level=1,msg="runCyclerTask(): WHY ARE WE HERE? In runCyclerTask with state %1?"},
			currentState, STATE_CYCLE)
		return -- do not schedule
	end

	-- See if log file needs to be opened
	if getVarNumeric("MaxLogSize", 0) > 0 then
		if logFile == false then -- false means we've never tried to open it
			pcall( logToFile, "Log file opened" )
		end
	elseif logFile then
		-- Needs to be closed.
		logFile:close()
		logFile = false
	end

	-- See if we're on time (early ticks come from restarts, usually)
	local nextStep = getVarNumeric("NextStep", 0, pluginDevice)
	if nextStep > now then
		D("runCyclerTask(): early step, delaying to %1", nextStep)
		setMessage( "Resuming; next at " .. os.date("%X", nextStep))
		task:schedule( nextStep )
		return
	end

	-- Ready to do some work.
	if currentState == STATE_SHUTDOWN then
		-- Shutting down. Find something else to turn off.
		D("runCyclerTask(): running off cycle")
		local hadLimited, nextLimited = turnOffLimited()
		-- Next cycle is sooner of random delay or next limited-time light (if any)
		local d = getRandomDelay("MinOffDelay", "MaxOffDelay", 60, 300)
		if nextLimited then
			d = math.min( d, nextLimited - now )
		end
		if not ( hadLimited or turnOffLight() ) then
			-- No more lights to turn off. Run final scene and don't reschedule this thread.
			clearLights() -- Make sure they're all out; runs final scene.
			L("All lights out; now idle, end of cycling until next activation.")
			setVar(MYSID, "State", STATE_IDLE, pluginDevice)
			setVar(MYSID, "NextStep", 0, pluginDevice)
			setMessage("Idle")
			return -- without rescheduling
		end
		D("runCyclerTask(): next cycle delay %1", d)
		task:delay( d )
		local wh = now + d
		setVar( MYSID, "NextStep", wh, pluginDevice )
		local m = "Deactivating; next at " .. os.date("%X", wh)
		L(m)
		setMessage(m)
		return
	end

	-- Cycling. Find a random target to control and control it.
	-- Start by making sure active flag is set.
	D("runCyclerTask(): running toggle cycle, state=%1", currentState)
	setVar(MYSID, "Active", "1", pluginDevice)

	-- Next cycle is sooner of random delay or next limited-time light (if any)
	local nextCycleDelay = getRandomDelay("MinCycleDelay", "MaxCycleDelay")
	local hadLimited, nextLimited = turnOffLimited()
	if nextLimited then
		nextCycleDelay = math.min( nextCycleDelay, nextLimited - now )
	end
	if not hadLimited then
		-- No limited-time light was turned off, so cycle something else.
		local devs, maxl = getTargetList()
		if maxl > 0 then
			local minOn = getVarNumeric("MinTargetsOn", 1)
			if minOn > maxl then minOn = maxl end
			local maxOn = getVarNumeric("MaxTargetsOn", 0)
			if maxOn < minOn then maxOn = 0 end
			local on, n = getTargetsOn()
			D("runCyclerTask(): currently %1 listed, %2 on, min %3, max %4", maxl, n, minOn, maxOn)
			-- Pick a device (loop until we do something)
			local attempts = 0
			while attempts < 10 do
				attempts = attempts + 1
				local change = math.random(1, maxl)
				local devspec = devs[change]
				if devspec ~= nil then
					local s = isDeviceOn(devspec)
					D("runCyclerTask(): attempt %1 chose %2 state %3", attempts, devspec, s)
					if s ~= nil then
						--[[ Valid device. If it's on, turn it off, unless
							 that puts us below the minimum number of lights
							 on; otherwise, turn something on.
						--]]
						if s and n > minOn then
							-- It's on and it's OK to turn if off.
							L("Cycle: turn %1 OFF", devspec)
							targetControl(devspec, false)
							break
						end
						if not s then
							-- It's off. If we're at/over maxOn, turn something else off.
							if maxOn > 0 and n >= maxOn then
								L("Cycle: %1 on, max is %2; turning something OFF", n, maxOn)
								turnOffLight(on)
							else
								L("Cycle: turn %1 ON", devspec)
								local maxOnTime = targetControl(devspec, true)
								if maxOnTime then nextCycleDelay = math.min(nextCycleDelay, maxOnTime) end
							end
							break
						end
						-- Didn't manipulate light; choose another and try again.
					end
				end
				D("runCyclerTask(): %1 ineligible, making another attempt", devspec)
			end
			D("runCyclerTask(): step complete after %1 attempts", attempts)
		end
	end

	-- Arm for next cycle
	D("runCyclerTask(): cycle finished, next in %1 seconds", nextCycleDelay)
	if nextCycleDelay < 15 then nextCycleDelay = 15 end
	nextStep = now + nextCycleDelay
	setVar(MYSID, "NextStep", nextStep, pluginDevice)
	task:schedule( nextStep )
	local m = "Cycling; next at " .. os.date("%X", nextStep)
	L(m)
	setMessage(m)
end

-- Check house mode.
local function checkHouseMode()
	D("checkHouseMode()")

	-- This is only relevant if we are checking house mode.
	local houseModes = getVarNumeric("HouseModes", 0)
	if houseModes ~= 0 then
		local newmode = tonumber( luup.attr_get("Mode", 0) or 1 ) or 1
		local lastMode = getVarNumeric( "LastHouseMode", 1, pluginDevice )
		if newmode == lastMode then return end
		setHMTModeSetting( systemHMD ) -- update/reset, always
		setVar( MYSID, "LastHouseMode", newmode, pluginDevice )
		sysTaskManager.getTask( "master" ):delay( 0 ) -- kick master task
		return true
	end
	return false
end

local function runHouseModeDefaultTask( task, dev )
	D("runHouseModeDefaultTask(%1,%2)", task, dev)
	if isEnabled() then
		task:delay( 60 )
		checkHouseMode()
	end
end

-- Initialize.
function deusInit(pdev)
	D("deusInit(%1)", pdev)
	L("starting plugin version %2 device %1", pdev, _PLUGIN_VERSION)

	if pluginDevice >= 0 then
		setMessage("Another Deus is running!", pdev)
		return false
	end
	pluginDevice = pdev

	if getVarNumeric("MaxLogSize", 0) > 0 then
		pcall( logToFile, "startup" )
	end

	maxEvents = getVarNumeric( "MaxEvents", 300, pdev )
	if maxEvents < 1 then maxEvents = 1 end

	if getVarNumeric( "DebugMode", 0, pdev ) ~= 0 then
		debugMode = true
		D("deusInit() debug mode enabled by state variable")
	end

	setMessage("Initializing...")

	sysTaskManager = TaskManager( 'deusTick' )

	-- Check UI version
	checkVersion(pdev)

	-- One-time stuff
	runOnce(pdev)

	math.randomseed( os.time() )

	-- Check for ALTUI and OpenLuup, HMD.
	for k,v in pairs(luup.devices) do
		if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
			local rc,rs,jj,ra
			D("deusInit() detected ALTUI at %1", k)
			isALTUI = true
			rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
				{ newDeviceType=MYTYPE, newScriptFile="J_DeusExMachinaII1_ALTUI.js", newDeviceDrawFunc="DeusExMachina_ALTUI.DeviceDraw" },
				k )
			D("deusInit() ALTUI's RegisterPlugin action returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra)
		elseif v.device_type == "openLuup" and v.device_num_parent == 0 then
			D("deusInit() detected openLuup")
			isOpenLuup = k
		end
	end

	-- House mode tracking
	if isOpenLuup then
		luup.variable_watch( "deusWatch", "openLuup", "HouseMode", isOpenLuup)
	else
		systemHMD = getHouseModeTracker( true, pdev )
		if systemHMD then
			D("deusInit(): watching system HMD device #%1", systemHMD)
			luup.attr_set( "invisible", debugMode and 0 or 1, systemHMD )
			luup.attr_set( "hidden", debugMode and 0 or 1, systemHMD )
			luup.attr_set( "room", luup.attr_get( "room", pdev ) or "0", systemHMD )
			setVar( "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", "0", systemHMD )
			setHMTModeSetting( systemHMD )
			luup.variable_watch( "deusWatch", "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", systemHMD )
		end

		-- Create and start the house mode poller ask fallback to HMD
		if getVarNumeric("PollHouseMode",0) ~= 0 then
			t = sysTaskManager.Task:new( "hmpoll", pluginDevice, runHouseModeDefaultTask, { pluginDevice } )
			t:delay( 60 )
		end
	end

	-- Other initialization

	-- Watch our own state, so we can track.
	luup.variable_watch("deusWatch", MYSID, "State", pdev)

	-- Create and start master tick task.
	local t = sysTaskManager.Task:new( "master", pluginDevice, runMasterTask, { pluginDevice } )
	t:delay( 15 )

	-- Create cycler task. Start up if last known state was active.
	t = sysTaskManager.Task:new( "cycler", pluginDevice, runCyclerTask, { pluginDevice } )
	local lastState = getVarNumeric( "State", STATE_STANDBY, pluginDevice )
	if lastState == STATE_CYCLE or lastState == STATE_SHUTDOWN then
		setMessage("Resuming after restart...")
		t:delay( 30 )
	end

	luup.set_failure( 0, pdev )
	return true, "OK", _PLUGIN_NAME
end

-- Watch callback
function deusWatch( dev, sid, var, oldVal, newVal )
	D("deusWatch(%1,%2,%3,%4,%5)", dev, sid, var, oldVal, newVal)
	if systemHMD and dev == systemHMD then
		-- House mode tracker state change.
		L("Detected house mode change by HMT (#%1)", dev)
		-- Defer polling task if it's running.
		if isEnabled() then
			local task = sysTaskManager.getTask( 'hmpoll' )
			if task then task:delay( 60, { replace=true } ) end -- defer poll
			checkHouseMode() -- also updates/resets HMT
		end
	elseif isOpenLuup and dev == isOpenLuup and var == "HouseMode" then
		L("openLuup house mode change detected from %1 to %2", oldVal, newVal)
		if isEnabled() then
			checkHouseMode()
		end
	elseif sid == MYSID and var == "State" then
		-- Turn off active flag in inactive states. Cycler turns flag on when it's working.
		local state = tonumber(newVal)
		if not (state == STATE_CYCLE or state == STATE_SHUTDOWN) then
			setVar( MYSID, "Active", "0", dev )
		end
	end
end

-- Tick handler for timing--changing running state based on current time.
function deusTick( stamp )
	dev = tonumber(dev,10)
	D("deusTick(%1)", stamp)
	sysTaskManager.runReadyTasks( stamp )
end

-- A "safer" JSON encode for Lua structures that may contain recursive refereance.
-- This output is intended for display ONLY, it is not to be used for data transfer.
local stringify
local function alt_json_encode( st, seen )
	seen = seen or {}
	str = "{"
	local comma = false
	for k,v in pairs(st) do
		str = str .. ( comma and "," or "" )
		comma = true
		str = str .. '"' .. k .. '":'
		if type(v) == "table" then
			if seen[v] then str = str .. '"(recursion)"'
			else
				seen[v] = k
				str = str .. alt_json_encode( v, seen )
			end
		else
			str = str .. stringify( v, seen )
		end
	end
	str = str .. "}"
	return str
end

-- Stringify a primitive type
stringify = function( v, seen )
	if v == nil then
		return "(nil)"
	elseif type(v) == "number" or type(v) == "boolean" then
		return tostring(v)
	elseif type(v) == "table" then
		return alt_json_encode( v, seen )
	end
	return string.format( "%q", tostring(v) )
end

local function getDevice( dev, pdev, v ) -- luacheck: ignore 212
	if v == nil then v = luup.devices[dev] end
	if json == nil then json = require("dkjson") end
	local devinfo = {
		  devNum=dev
		, ['type']=v.device_type
		, description=v.description or ""
		, room=v.room_num or 0
		, udn=v.udn or ""
		, id=v.id
		, parent=v.device_num_parent
		, ['device_json'] = luup.attr_get( "device_json", dev )
		, ['impl_file'] = luup.attr_get( "impl_file", dev )
		, ['device_file'] = luup.attr_get( "device_file", dev )
		, manufacturer = luup.attr_get( "manufacturer", dev ) or ""
		, model = luup.attr_get( "model", dev ) or ""
	}
	local rc,t,httpStatus,uri
	if isOpenLuup then
		uri = "http://localhost:3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
	else
		uri = "http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
	end
	rc,t,httpStatus = luup.inet.wget(uri, 15)
	if httpStatus ~= 200 or rc ~= 0 then
		devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
		return devinfo
	end
	local d = json.decode(t)
	local key = "Device_Num_" .. dev
	if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
	devinfo.states = d or {}
	return devinfo
end

function request( lul_request, lul_parameters, lul_outputformat )
	D("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
	local action = lul_parameters['action'] or lul_parameters['command'] or ""
	local deviceNum = tonumber( lul_parameters['device'] or "" ) or pluginDevice
	if action == "debug" then
		if lul_parameters.debug ~= nil then
			debugMode = (":1:true:yes:y:t"):match( lul_parameters.debug )
		else
			debugMode = not debugMode
		end
		D("debug set %1 by request", debugMode)
		return "Debug is now " .. ( debugMode and "on" or "off" ), "text/plain"

	elseif action == "status" then
		local st = {
			name=_PLUGIN_NAME,
			plugin=_PLUGIN_ID,
			version=_PLUGIN_VERSION,
			configversion=_CONFIGVERSION,
			author="Patrick H. Rigney (rigpapa)",
			url=_PLUGIN_URL,
			['type']=MYTYPE,
			responder=luup.device,
			timestamp=os.time(),
			system = {
				version=luup.version,
				isOpenLuup=isOpenLuup,
				isALTUI=isALTUI,
				hardware=luup.attr_get("model",0),
				lua=tostring((_G or {})._VERSION),
				housemode=luup.attr_get("Mode",0),
				longitude=luup.longitude,
				latitude=luup.latitude
			},
			devices={},
			systemHMD=systemHMD,
			sysEvents=sysEvents,
			sysTasks=sysTaskManager._tt,
			devStateCache=devStateCache
		}
		for k,v in pairs( luup.devices ) do
			if v.device_type == MYTYPE or v.device_num_parent == deviceNum then
				local devinfo = getDevice( k, deviceNum, v ) or {}
				table.insert( st.devices, devinfo )
			end
		end
		st.controlled = {}
		local cd = split(luup.variable_get( MYSID, "Devices", deviceNum ) or "")
		if ( #cd > 1 or ( #cd == 1 and cd[1] ~= "" ) ) then
			for _,dd in ipairs(cd) do
				if dd:byte(1) == 83 then
					-- scene
					st.controlled[dd] = { ['type']="scene", control=dd }
				else
					local dev = tostring(dd or "-1"):match( "^(%d+)(.*)" )
					if not dev then
						st.controlled[dd] = { ['type']="unrecognized" }
					else
						devid = tonumber(dev)
						st.controlled[tostring(devid)] = { ['type']="device", control=dd, device=luup.devices[devid] or "(unknown)" }
						if ( ((luup.devices[devid] or {}).device_num_parent or 0) ~= 0 ) then
							local n = tonumber( luup.devices[devid].device_num_parent )
							st.controlled[tostring(n)] = { ['type']="parent", device=luup.devices[n] or "(unknown)" }
						end
					end
				end
			end
		end

		return alt_json_encode( st ), "application/json"

	else
		error("Not implemented: " .. action)
	end
end
