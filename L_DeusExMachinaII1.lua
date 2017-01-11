module("L_DeusExMachinaII1", package.seeall)

local _VERSION = "2.4RC5"
local DEMVERSION = 20400

local SID = "urn:toggledbits-com:serviceId:DeusExMachinaII1"

local SWITCH_TYPE = "urn:schemas-upnp-org:device:BinaryLight:1"
local SWITCH_SID  = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_TYPE = "urn:schemas-upnp-org:device:DimmableLight:1"
local DIMMER_SID  = "urn:upnp-org:serviceId:Dimming1"

local STATE_STANDBY = 0
local STATE_IDLE = 1
local STATE_CYCLE = 2
local STATE_SHUTDOWN = 3

local runStamp = 0
local debugMode = true

local function debug(...)
    if debugMode then
        local str = "DeusExMachinaII1(dbg):" .. arg[1]
        local ipos = 1
        while true do
            local i, j, n
            i, j, n = string.find(str, "%%(%d+)", ipos)
            if i == nil then break end
            n = tonumber(n, 10)
            if n >= 1 and n < table.getn(arg) then
                if i == 1 then
                    str = tostring(arg[n+1]) .. string.sub(str, j+1)
                else
                    str = string.sub(str, 1, i-1) .. tostring(arg[n+1]) .. string.sub(str, j+1)
                end
            end
            ipos = j + 1
        end
        luup.log(str)
    end
end

local function checkVersion()
    local ui7Check = luup.variable_get(SID, "UI7Check", luup.device) or ""
    if ui7Check == "" then
        luup.variable_set(SID, "UI7Check", "false", luup.device)
        ui7Check = "false"
    end
    if ( luup.version_branch == 1 and luup.version_major == 7 and ui7Check == "false" ) then
        luup.variable_set(SID, "UI7Check", "true", luup.device)
        luup.attr_set("device_json", "D_DeusExMachinaII1_UI7.json", luup.device)
        luup.reload()
    end
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev )
    if dev == nil then dev = luup.device end
    local s = luup.variable_get(SID, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

-- Delete a variable (if we can... read on...)
local function deleteVar( name, devid )
    if (devid == nil) then devid = luup.device end
    -- Interestingly, setting a variable to nil with luup.variable_set does nothing interesting; too bad, it
    -- could have been used to delete variables, since a later get would yield nil anyway. But it turns out
    -- that using the variableget Luup request with no value WILL delete the variable.
    local req = "http://127.0.0.1:3480/data_request?id=variableset&amp;DeviceNum=" .. tostring(devid) .. "&amp;serviceId=" .. SID .. "&amp;Variable=" .. name .. "&amp;Value="
    debug("deleteVar(%1,%2) wget %3", name, devid, req)
    local status, result = luup.inet.wget(req)
    debug("deleteVar(%1,%2) status=%3, result=%4", name, devid, status, result)
end

local function pad(n)
    if (n < 10) then return "0" .. n end
    return n;
end

local function timeToString(t)
    if t == nil then t = os.time() end
    return pad(t['hour']) .. ':' .. pad(t['min']) .. ':' .. pad(t['sec'])
end

local function setMessage(s)
    luup.variable_set(SID, "Message", s or "", luup.device)
end

-- Shortcut function to return state of SwitchPower1 Status variable
local function isEnabled()
    local s = luup.variable_get(SWITCH_SID, "Status", luup.device)
    if (s == nil or s == "") then return false end
    return (s ~= "0")
end

local function isActiveHouseMode()
    -- Fetch our mask bits that tell us what modes we operate in. If 0, we're not checking house mode.
    local modebits = getVarNumeric("HouseModes", 0)
    if (modebits ~= 0) then
        -- Get the current house mode. There seems to be some disharmony in the correct way to go
        -- about this, but the method (uncommented) below works.
        local currentMode = luup.attr_get("Mode", 0) -- alternate method

        -- Check to see if house mode bits are non-zero, and if so, apply current mode as mask.
        -- If bit is set (current mode is in the bitset), we can run, otherwise skip.
        local bit = require("bit")
        -- Get the current house mode (1=Home,2=Away,3=Night,4=Vacation)
        currentMode = math.pow(2, tonumber(currentMode,10))
        if (bit.band(modebits, currentMode) == 0) then
            debug('DeusExMachinaII:isActiveHouseMode(): Current mode bit %1 not set in %2', string.format("0x%x", currentMode), string.format("0x%x", modebits))
            return false -- not active in this mode
        else
            debug('DeusExMachinaII:isActiveHouseMode(): Current mode bit %1 SET in %2', string.format("0x%x", currentMode), string.format("0x%x", modebits))
        end
    end
    return true -- default is we're active in the current house mode
end

-- Get a random delay from two state variables. Error check.
local function getRandomDelay(minStateName,maxStateName,defMin,defMax)
    if defMin == nil then defMin = 300 end
    if defMax == nil then defMax = 1800 end
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
            debug('getSunset(): testing mode sunset override %1, as timeval is %2', m, sunset)
        end
    end
    if (sunset <= os.time()) then sunset = sunset + 86400 end
    return sunset
end

local function getSunsetMSM()
    local t = os.date('*t', getSunset())
    return t['hour']*60 + t['min']
end

-- DEM cycles lights between sunset and the user-specified off time. This function returns 0
-- if the current time is between sunset and off; otherwise 1. Note that all times are reduced
-- to minutes-since-midnight units.
local function isBedtime()
    local testing = getVarNumeric("TestMode", 0)
    if (testing ~= 0) then 
        luup.log('DeusExMachinaII:isBedtime(): TestMode is on') 
        debugMode = true
    end

    -- Establish the lights-out time
    local bedtime = 1439 -- that's 23:59 in minutes since midnight (default)
    local bedtime_tmp = luup.variable_get(SID, "LightsOut", luup.device)
    if (bedtime_tmp ~= nil) then
        bedtime_tmp = tonumber(bedtime_tmp,10)
        if (bedtime_tmp >= 0 and bedtime_tmp < 1440) then bedtime = bedtime_tmp end
    end

    -- Figure out our sunset time.
    local sunset = getSunsetMSM()

    -- And the current time.
    local date = os.date('*t')
    local time = date['hour'] * 60 + date['min']

    -- Figure out if we're betweeen sunset and lightout (ret=0) or not (ret=1)
    debug('isBedtime(): times (mins since midnight) are now=%1, sunset=%2, bedtime=%3', time, sunset, bedtime)
    local ret = 1 -- guilty until proven innocent
    if (bedtime > sunset) then
            -- Case 1: bedtime is after sunset (i.e. between sunset and midnight)
        if (time >= sunset and time < bedtime) then
            ret = 0
        end
    else
            -- Case 2: bedtime is after midnight
        if (time >= sunset or time < bedtime) then
            ret = 0
        end
    end
    debug("isBedtime(): returning %1", ret)
    return ret
end

-- Take a string and split it around sep, returning table (indexed) of substrings
-- For example abc,def,ghi becomes t[1]=abc, t[2]=def, t[3]=ghi
-- Returns: table of values, count of values (integer ge 0)
local function split(s, sep)
    local t = {}
    local n = 0
    if (#s == 0) then return t,n end -- empty string returns nothing
    local i,j
    local k = 1
    repeat
        i, j = string.find(s, sep or "%s*,%s*", k)
        if (i == nil) then
            table.insert(t, string.sub(s, k, -1))
            n = n + 1
            break
        else
            table.insert(t, string.sub(s, k, i-1))
            n = n + 1
            k = j + 1
        end
    until k > string.len(s)
    return t, n
end

-- Return true if a specified scene has been run (i.e. on the list)
local function isSceneOn(spec)
    local stateList = luup.variable_get(SID, "ScenesRunning", luup.device) or ""
    for i in string.gfind(stateList, "[^,]+") do
        if (i == spec) then return true end
    end
    return false
end

-- Mark or unmark a scene as having been run
local function updateSceneState(spec, isOn)
    local stateList = luup.variable_get(SID, "ScenesRunning", luup.device) or ""
    local i
    local t = {}
    for i in string.gfind(stateList, "[^,]+") do
        t[i] = 1
    end
    if (isOn) then
        t[spec] = 1
    else
        t[spec] = nil
    end
    stateList = ""
    for i in pairs(t) do stateList = stateList .. "," .. tostring(i) end
    luup.variable_set(SID, "ScenesRunning", string.sub(stateList, 2, -1), luup.device)
end

-- Run "final" scene, if defined. This scene is run after all other targets have been
-- turned off.
local function runFinalScene()
    local scene  = getVarNumeric("FinalScene", nil)
    if (scene ~= nil) then
        debug("runFinalScene(): running final scene %1", scene)
        luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=scene }, 0)
    end
end

-- Get the list of targets from our device state, parse to table of targets.
local function getTargetList()
    local s = luup.variable_get(SID, "Devices", luup.device) or ""
    return split(s)
end

-- Remove a target from the target list. Used when the target no longer exists. Linear, poor, but short list and rarely used.
local function removeTarget(target, tlist)
    if tlist == nil then tlist = getTargetList() end
    local i
    for i = 1,table.getn(tlist) do
        if tostring(target) == tlist[i] then
            table.remove(tlist, i)
            luup.variable_set(SID, "Devices", table.concat(tlist, ","), deusDevuce)
            return true
        end
    end
    return false
end

-- Light on or off? Returns boolean
local function isDeviceOn(targetid)
    local first = string.upper(string.sub(targetid, 1, 1))
    if (first == "S") then
        debug("isDeviceOn(): handling scene spec %1", targetid)
        return isSceneOn(targetid)
    end

    -- Handle as switch or dimmer
    debug("isDeviceOn(): handling target spec %1", targetid)
    local r = tonumber(string.match(targetid, '^%d+'), 10)
    local val = "0"
    if (luup.devices[r] ~= nil) then
        if luup.device_supports_service(DIMMER_SID, r) then
            val = luup.variable_get(DIMMER_SID, "LoadLevelStatus", r)
        elseif luup.device_supports_service(SWITCH_SID, r) then
            val =  luup.variable_get(SWITCH_SID, "Status", r)
        end
    else
        luup.log("DeusExMachinaII:isDeviceOn(): target spec " .. tostring(targetid) .. ", device " .. tostring(r) .. " not found in luup.devices")
        removeTarget(targetid)
        return nil
    end
    return val ~= "0"
end

-- Control target. Target is a string, expected to be a pure integer (in which case the target is assumed to be a switch or dimmer),
-- or a string in the form Sxx:yy, in which case xx is an "on" scene to run, and yy is an "off" scene to run.
local function targetControl(targetid, turnOn)
    debug("targetControl(): targetid=%1, turnOn=%2", targetid, turnOn)
    local first = string.upper(string.sub(targetid, 1, 1))
    if first == "S" then
        debug("targetControl(): handling as scene spec %1", targetid)
        i, j, onScene, offScene = string.find(string.sub(targetid, 2), "(%d+)-(%d+)")
        if (i == nil) then
            luup.log("DeusExMachina:targetControl(): malformed scene spec=" .. tostring(targetid))
            return
        end
        onScene = tonumber(onScene, 10)
        offScene = tonumber(offScene, 10)
        if luup.scenes[onScene] == nil or luup.scenes[offScene] == nil then
            -- Both on scene and off scene must exist (defensive).
            luup.log("DeusExMachinaII:targetControl(): one or both of the scenes in " .. tostring(targetid) .. " not found in luup.scenes!")
            removeTarget(targetid)
            return
        end
        debug("targetControl(): on scene is %1, off scene is %2", onScene, offScene)
        local targetScene
        if turnOn then targetScene = onScene else targetScene = offScene end
        luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=targetScene }, 0)
        updateSceneState(targetid, turnOn)
    else
        -- Parse the level if this is a dimming target spec
        local lvl = 100
        local k = string.find(targetid, '=')
        if k ~= nil then
            _, _, targetid, lvl = string.find(targetid, "(%d+)=(%d+)")
            lvl = tonumber(lvl, 10)
        end
        targetid = tonumber(targetid, 10)
        -- Level for all types is 0 if turning device off
        if not turnOn then lvl = 0 end
        if luup.devices[targetid] == nil then
            -- Device doesn't exist (user deleted, etc.). Remove from Devices state variable.
            luup.log("DeusExMachinaII:targetControl(): device " .. tostring(targetid) .. " not found in luup.devices")
            removeTarget(targetid)
            return
        end
        if luup.device_supports_service(DIMMER_SID, targetid) then
            -- Handle as Dimming1
            debug("targetControl(): handling %1 (%3) as dimmmer, set load level to %2", targetid, lvl, luup.devices[targetid].description)
            luup.call_action(DIMMER_SID, "SetLoadLevelTarget", {newLoadlevelTarget=lvl}, targetid) -- note odd case inconsistency
        elseif luup.device_supports_service(SWITCH_SID, targetid) then
            -- Handle as SwitchPower1
            if turnOn then lvl = 1 end
            debug("targetControl(): handling %1 (%3) as switch, set target to %2", targetid, lvl, luup.devices[targetid].description)
            luup.call_action(SWITCH_SID, "SetTarget", {newTargetValue=lvl}, targetid)
        else
            luup.log("DeusExMachinaII:targetControl(): don't know how to control target " .. tostring(targetid))
        end
    end
end

-- Get list of targets that are on
local function getTargetsOn()
    local devs, max
    local on = {}
    local n = 0
    devs,max = getTargetList()
    if (max > 0) then
        local i
        for i = 1,max do
            local devOn = isDeviceOn(devs[i])
            if (devOn ~= nil and devOn) then
                table.insert(on, devs[i])
                n = n + 1
            end
        end
    end
    return on,n
end

-- Turn off a light, if any is on. Returns 1 if there are more lights to turn off; otherwise 0.
local function turnOffLight(on)
    local n
    if on == nil then
        on, n = getTargetsOn()
    else
        n = table.getn(on)
    end
    if (n > 0) then
        local i = math.random(1, n)
        local target = on[i]
        targetControl(target, false)
        table.remove(on, i)
        n = n - 1
        debug("turnOffLight(): turned %1 OFF, still %2 targets on", target, n)
    end
    return (n > 0), on, n
end

-- Turn off all lights as fast as we can. Transition through SHUTDOWN state during,
-- in case user has any triggers connected to that state. The caller must immediately
-- set the next state when this function returns (expected would be STANDBY or IDLE).
local function clearLights()
    local devs, count
    devs, count = getTargetList()
    luup.variable_set(SID, "State", STATE_SHUTDOWN, luup.device)
    while count > 0 do
        targetControl(devs[count], false)
        count = count - 1
    end
    runFinalScene()
end

-- runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place. For us, that means looking to see if an older version of Deus is still
-- installed, and copying its config into our new config. Then disable the old Deus.
local function runOnce()
    local s = luup.variable_get(SID, "Devices", luup.device)
    if (s == nil) then
        luup.log("DeusExMachinaII:runOnce(): Devices variable not found, setting up new instance...")
        -- See if there are variables from older version of DEM
        -- Start by finding the old Deus device, if there is one...
        local devList = ""
        local i, olddev
        olddev = -1
        for i,v in pairs(luup.devices) do
            if (v.device_type == "urn:schemas-futzle-com:device:DeusExMachina:1") then
                luup.log("DeusExMachinaII:runOnce(): Found old Deus Ex Machina device #" .. tostring(i))
                olddev = i
                break
            end
        end
        if (olddev > 0) then
            -- We found an old Deus device, copy its config into our new state variables
            local oldsid = "urn:futzle-com:serviceId:DeusExMachina1"
            s = luup.variable_get(oldsid, "LightsOutTime", olddev)
            if (s ~= nil) then
                local n = tonumber(s,10) / 60000
                luup.variable_set(SID, "LightsOut", n, luup.device)
                deleteVar("LightsOutTime", luup.device)
            end
            s = luup.variable_get(oldsid, "controlCount", olddev)
            if (s ~= nil) then
                local n = tonumber(s, 10)
                local k
                local t = {}
                for k = 1,n do
                    s = luup.variable_get(oldsid, "control" .. tostring(k-1), olddev)
                    if (s ~= nil) then
                        table.insert(t, s)
                    end
                end
                devList = table.concat(t, ",")
                deleteVar("controlCount", luup.device)
            end

            -- Finally, turn off old Deus
            luup.call_action(oldsid, "SetEnabled", { NewEnabledValue = "0" }, olddev)
        end
        luup.variable_set(SID, "Devices", devList, luup.device)

        -- Set up some other default config
        luup.variable_set(SID, "MinCycleDelay", "300", luup.device)
        luup.variable_set(SID, "MaxCycleDelay", "1800", luup.device)
        luup.variable_set(SID, "MinOffDelay", "60", luup.device)
        luup.variable_set(SID, "MaxOffDelay", "300", luup.device)
        luup.variable_set(SID, "LightsOut", 1439, luup.device)
        luup.variable_set(SID, "MaxTargetsOn", 0, luup.device)
        luup.variable_set(SID, "Enabled", "0", luup.device)
        luup.variable_set(SID, "Version", DEMVERSION, luup.device)
        luup.variable_set(SWITCH_SID, "Status", "0", luup.device)
        luup.variable_set(SWITCH_SID, "Target", "0", luup.device)
    end

    -- Consider per-version changes.
    s = getVarNumeric("Version", 0)
    if (s < 20300) then
        -- v2.3: LightsOutTime (in milliseconds) deprecated, now using LightsOut (in minutes since midnight)
        luup.log("DeusExMachinaII:runOnce(): updating config, version " .. tostring(s) .. " < 20300")
        s = luup.variable_get(SID, "LightsOut", luup.device)
        if (s == nil) then
            s = getVarNumeric("LightsOutTime") -- get pre-2.3 variable
            if (s == nil) then
                luup.variable_set(SID, "LightsOut", 1439, luup.device) -- default 23:59
            else
                luup.variable_set(SID, "LightsOut", tonumber(s,10) / 60000, luup.device) -- conv ms to minutes
            end
        end
        deleteVar("LightsOutTime", luup.device)
    end
    if (s < 20400) then
        -- v2.4: SwitchPower1 variables added. Follow previous plugin state in case of auto-update.
        luup.log("DeusExMachinaII:runOnce(): updating config, version " .. tostring(s) .. " < 20400")
        luup.variable_set(SID, "MaxTargetsOn", 0, luup.device)
        local e = getVarNumeric("Enabled", 0)
        luup.variable_set(SWITCH_SID, "Status", e, luup.device)
        luup.variable_set(SWITCH_SID, "Target", e, luup.device)
    end

    -- Update version state last.
    if (s ~= DEMVERSION) then
        luup.variable_set(SID, "Version", DEMVERSION, luup.device)
    end
end

-- Return the plugin version string
function getVersion()
    return _VERSION, DEMVERSION
end

-- Enable DEM by setting a new cycle stamp and scheduling our first cycle step.
function deusEnable()
    luup.log("DeusExMachinaII:deusEnable(): enabling, luup.device=" .. tostring(luup.device))
    luup.variable_set(SWITCH_SID, "Target", "1", luup.device)

    setMessage("Enabling...")

    luup.variable_set(SWITCH_SID, "Status", "1", luup.device)
    luup.variable_set(SID, "Enabled", "1", luup.device)

    runStamp = os.time()

    luup.call_delay("deusStep", 1, runStamp)
    debug("deusEnable(): scheduled first step, done")
end

-- Disable DEM and go to standby state. If we are currently cycling (as opposed to idle/waiting for sunset),
-- turn off any controlled lights that are on.
function deusDisable()
    luup.log("DeusExMachinaII:deusDisable(): disabling, luup.device=" .. tostring(luup.device))
    luup.variable_set(SWITCH_SID, "Target", "0", luup.device)

    setMessage("Disabling...")
    
    -- Destroy runStamp so any thread running while we shut down just exits.
    runStamp = 0

    local s = getVarNumeric("State", STATE_STANDBY)
    if ( s == STATE_CYCLE or s == STATE_SHUTDOWN ) then
        clearLights()
    end

    luup.variable_set(SID, "ScenesRunning", "", luup.device) -- start with a clean slate next time
    luup.variable_set(SID, "State", STATE_STANDBY, luup.device)
    luup.variable_set(SID, "Enabled", "0", luup.device)
    luup.variable_set(SWITCH_SID, "Status", "0", luup.device)

    setMessage("")
end

-- Initialize.
function deusInit(pdev)
    luup.log("DeusExMachinaII:deusInit(" .. tostring(pdev) .. "): Version " .. _VERSION .. ", initializing, luup.device=" .. tostring(luup.device))

    runStamp = 0
    
    setMessage("Initializing...")
    
    if debugMode or true then
        local status, body, httpStatus
        status, body, httpStatus = luup.inet.wget("http://127.0.0.1:3480/data_request?id=status&DeviceNum=" .. tostring(luup.device) .. "&output_format=json")
        debug("deusInit(): status %2, startup state is %1", body, status)
    end

    -- One-time stuff
    runOnce()

    -- Check UI version
    checkVersion()

    -- Start up if we're enabled
    if (isEnabled()) then
        deusEnable()
    else
        deusDisable()
    end
end

-- Run a cycle. If we're in "bedtime" (i.e. not between our cycle period between sunset and stop),
-- then we'll shut off any lights we've turned on and queue another run for the next sunset. Otherwise,
-- we'll toggled one of our controlled lights, and queue (random delay, but soon) for another cycle.
-- The shutdown of lights also occurs randomly, but can (through device state/config) have different
-- delays, so the lights going off looks more "natural" (i.e. not all at once just slamming off).
function deusStep(stepStampCheck)
    local stepStamp = tonumber(stepStampCheck)
    luup.log("DeusExMachinaII:deusStep(): wakeup, stamp " .. tostring(stepStampCheck) .. ", luup.device=" .. tostring(luup.device))
    if (stepStamp ~= runStamp) then
        luup.log("DeusExMachinaII:deusStep(): stamp mismatch, another thread running. Bye!")
        return
    end
    if (not isEnabled()) then
        luup.log("DeusExMachinaII:deusStep(): not enabled, no more work for this thread...")
        return
    end

    -- Get next sunset as seconds since midnight (approx)
    local sunset = getSunset()

    local currentState = getVarNumeric("State", 0)
    if (currentState == STATE_STANDBY or currentState == STATE_IDLE) then
        debug("deusStep(): step in state %1, lightsout=%2, sunset=%3, os.time=%4", currentState,
            luup.variable_get(SID, "LightsOut", luup.device), sunset, os.time())
        debug("deusStep(): luup variables longitude=%1, latitude=%2, timezone=%3, city=%4, sunset=%5, version=%6",
            luup.longitude, luup.latitude, luup.timezone, luup.city, luup.sunset(), luup.version)
    end

    local inActiveTimePeriod = true
    if (isBedtime() ~= 0) then
        debug("deusStep(): in lights out time")
        inActiveTimePeriod = false
    end
    
    -- Get going...
    local nextCycleDelay = 300 -- a default value to keep us out of hot water
    if (currentState == STATE_STANDBY and not inActiveTimePeriod) then
            -- Transition from STATE_STANDBY (i.e. we're enabling) in the inactive period.
            -- Go to IDLE and delay for next sunset.
            luup.log("DeusExMachinaII:deusStep(): transitioning to IDLE from STANDBY, waiting for next sunset...")
            nextCycleDelay = sunset - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
            luup.variable_set(SID, "State", STATE_IDLE, luup.device)
            setMessage("Waiting for sunset " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
    elseif (not isActiveHouseMode()) then
        -- Not in an active house mode. If we're not STANDBY or IDLE, turn everything back off and go to IDLE.
        if (currentState ~= STATE_IDLE) then
            luup.log("DeusExMachinaII:deusStep(): transitioning to IDLE, not in an active house mode.")
            if (currentState ~= STATE_STANDBY) then clearLights() end -- turn off lights quickly unless transitioning from STANDBY
            luup.variable_set(SID, "State", STATE_IDLE, luup.device)
        else
            luup.log("DeusExMachinaII:deusStep(): IDLE in an inactive house mode; waiting for mode change.")
        end

        -- Figure out how long to delay. If we're lights-out, delay to next sunset. Otherwise, short delay
        -- to re-check house mode, which could change at any time, so we must deal with it.
        if (inActiveTimePeriod) then
            nextCycleDelay = getRandomDelay("MinCycleDelay", "MaxCycleDelay")
        else
            nextCycleDelay = sunset - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
        end
        setMessage("Waiting for active house mode")
    elseif (not inActiveTimePeriod) then
        luup.log("DeusExMachinaII:deusStep(): running off cycle")
        luup.variable_set(SID, "State", STATE_SHUTDOWN, luup.device)
        if (not turnOffLight()) then
            -- No more lights to turn off
            runFinalScene()
            luup.variable_set(SID, "State", STATE_IDLE, luup.device)
            nextCycleDelay = sunset - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
            luup.log("DeusExMachina:deusStep(): all lights out; now IDLE, setting delay to restart cycling at next sunset")
            setMessage("Waiting for sunset " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        else
            nextCycleDelay = getRandomDelay("MinOffDelay", "MaxOffDelay", 60, 300)
            setMessage("Shut-off cycle, next " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        end
    else
        -- Fully active. Find a random target to control and control it.
        luup.log("DeusExMachinaII:deusStep(): running toggle cycle")
        luup.variable_set(SID, "State", STATE_CYCLE, luup.device)
        nextCycleDelay = getRandomDelay("MinCycleDelay", "MaxCycleDelay")
        local devs, max
        devs, max = getTargetList()
        if (max > 0) then
            local change = math.random(1, max)
            local devspec = devs[change]
            if (devspec ~= nil) then
                local s = isDeviceOn(devspec)
                if (s ~= nil) then
                    if (s) then
                        -- It's on; turn it off.
                        debug("deusStep(): turn %1 OFF", devspec)
                        targetControl(devspec, false)
                    else
                        -- Turn something on. If we're at the max number of targets we're allowed to turn on,
                        -- turn targets off first.
                        local maxOn = getVarNumeric("MaxTargetsOn")
                        if (maxOn == nil) then maxOn = 0 else maxOn = tonumber(maxOn,10) end
                        if (maxOn > 0) then
                            local on, n
                            on, n = getTargetsOn()
                            while ( n >= maxOn ) do
                                debug("deusStep(): too many targets on, max is %1, have %2, turning one off", maxOn, n)
                                _, on, n = turnOffLight(on)
                            end
                        end
                        debug("deusStep(): turn %1 ON", devspec)
                        targetControl(devspec, true)
                    end
                end
            end
            setMessage("Cycling; next " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        else
            setMessage("Nothing to do")
            luup.log("DeusExMachinaII:deusStep(): no targets to control")
        end
    end

    -- Arm for next cycle
    if nextCycleDelay ~= nil then
        luup.log("DeusExMachinaII:deusStep(): cycle finished, next in " .. nextCycleDelay .. " seconds")
        if nextCycleDelay < 1 then nextCycleDelay = 60 end
        luup.call_delay("deusStep", nextCycleDelay, stepStamp)
    else
        luup.log("DeusExMachinaII:deusStep(): nil nextCycleDelay, next cycle not scheduled!")
    end
end
