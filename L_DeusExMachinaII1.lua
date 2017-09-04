-- L_DeusExMachinaII1.lua - Core module for DeusExMachinaII
-- Copyright 2016,2017 Patrick H. Rigney, All Rights Reserved.
-- This file is part of DeusExMachinaII. For license information, see LICENSE at https://github.com/toggledbits/DeusExMachina

module("L_DeusExMachinaII1", package.seeall)

local _PLUGIN_NAME = "DeusExMachinaII"
local _PLUGIN_VERSION = "2.5"
local _CONFIGVERSION = 20500

local MYSID = "urn:toggledbits-com:serviceId:DeusExMachinaII1"
local MYTYPE = "urn:schemas-toggledbits-com:device:DeusExMachinaII:1"

local SWITCH_TYPE = "urn:schemas-upnp-org:device:BinaryLight:1"
local SWITCH_SID  = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_TYPE = "urn:schemas-upnp-org:device:DimmableLight:1"
local DIMMER_SID  = "urn:upnp-org:serviceId:Dimming1"

local STATE_STANDBY = 0
local STATE_IDLE = 1
local STATE_CYCLE = 2
local STATE_SHUTDOWN = 3

local myDevice = 0
local runStamp = 0
local isALTUI = false
local isOpenLuup = false

local debugMode = true

local function dump(t)
    if t == nil then return "nil" end
    local k,v,str,val
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
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

local function L(msg, ...)
    local str
    if type(msg) == "table" then
        str = msg["prefix"] .. msg["msg"]
    else
        str = _PLUGIN_NAME .. ": " .. msg
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
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
    luup.log(str)
end

local function D(msg, ...)
    if debugMode then
        L( { msg=msg,prefix=(_PLUGIN_NAME .. "::") }, unpack(arg) )
    end
end

local function checkVersion(dev)
    local ui7Check = luup.variable_get(MYSID, "UI7Check", dev) or ""
    if isOpenLuup or ( luup.version_branch == 1 and luup.version_major >= 7 ) then
        if ui7Check == "" then
            -- One-time init for UI7 or better
            luup.variable_set(MYSID, "UI7Check", "true", dev)
        end
    elseif luup.version_branch == 1 and luup.version_major < 5 then
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
local function getVarNumeric( name, dflt, dev )
    if dev == nil then dev = myDevice end
    local s = luup.variable_get(MYSID, name, dev)
    if (s == nil or s == "") then return dflt end
    s = tonumber(s, 10)
    if (s == nil) then return dflt end
    return s
end

-- Delete a variable (if we can... read on...)
local function deleteVar( name, devid )
    if devid == nil then devid = myDevice end
    -- Interestingly, setting a variable to nil with luup.variable_set does nothing interesting; too bad, it
    -- could have been used to delete variables, since a later get would yield nil anyway. But it turns out
    -- that using the variableset Luup request with no value WILL delete the variable.
    local req = "http://127.0.0.1:3480/data_request?id=variableset&DeviceNum=" .. tostring(devid) .. "&serviceId=" .. MYSID .. "&Variable=" .. name .. "&Value="
    D("deleteVar(%1,%2) wget %3", name, devid, req)
    local status, result = luup.inet.wget(req)
    D("deleteVar(%1,%2) status=%3, result=%4", name, devid, status, result)
end

local function pad(n)
    if (n < 10) then return "0" .. n end
    return n;
end

local function timeToString(t)
    if t == nil then t = os.time() end
    return pad(t['hour']) .. ':' .. pad(t['min']) .. ':' .. pad(t['sec'])
end

local function setMessage(s, dev)
    if dev == nil then dev = myDevice end
    luup.variable_set(MYSID, "Message", s or "", dev)
end

-- Shortcut function to return state of SwitchPower1 Status variable
local function isEnabled()
    local s = luup.variable_get(SWITCH_SID, "Target", myDevice)
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
        -- Get the current house mode (1=Home,2=Away,3=Night,4=Vacation) and mode into bit position.
        currentMode = math.pow(2, tonumber(currentMode,10))
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
            D('getSunset(): testing mode sunset override %1, as timeval is %2', m, sunset)
        end
    end
    if (sunset <= os.time()) then sunset = sunset + 86400 end
    return sunset
end

local function getSunsetMSM()
    local t = os.date('*t', getSunset())
    return t['hour']*60 + t['min']
end

-- Return start time in seconds. Could be configured, could be sunset.
local function startTime(dev)
    local st = luup.variable_get(MYSID, "StartTime", dev)
    D("startTime() start time=%1",st)
    if st == nil or string.match(st, "^%s*$") then 
        st = getSunset()
        local tt = os.date("*t", st)
        return st, string.format("sunset (%02d:%02d)", tt.hour, tt.min)
    else
        local tt = os.date("*t")
        tt.hour = math.floor(st/60)
        tt.min = st % 60
        tt.sec = 0
        local ts = os.time(tt)
        D("tt=%1, ts=%2",tt, ts)
        if ts < os.time() then ts = ts + 86400 end
        return ts, string.format("%02d:%02d", tt.hour, tt.min)
    end
end

-- DEM cycles lights between start and lights-out. This function returns 0 if 
-- the current time is between start and lights-out; otherwise 1. Note that all
-- times are reduced to minutes-since-midnight.
local function isBedtime()
    local testing = getVarNumeric("TestMode", 0)
    if (testing ~= 0) then 
        L('isBedtime(): TestMode is on') 
        debugMode = true
    end

    -- Establish the lights-out time
    local bedtime = 1439 -- that's 23:59 in minutes since midnight (default)
    local bedtime_tmp = luup.variable_get(MYSID, "LightsOut", myDevice)
    if (bedtime_tmp ~= nil) then
        bedtime_tmp = tonumber(bedtime_tmp,10)
        if (bedtime_tmp >= 0 and bedtime_tmp < 1440) then bedtime = bedtime_tmp end
    end

    -- Figure out our start time in MSM
    local start = os.date('*t', startTime(myDevice))
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

-- Quick and dirty serialization of our simple data structure
local function save(name, value, sep)
    if sep == nil then sep = "" end
    local str = sep .. name .. "="
    if type(value) == "table" then
        str = str .. "{"   -- create a new table
        sep = ""
        for k,v in pairs(value) do      -- save its fields
            str = str .. save(string.format("[%q]", k), v, sep)
            sep = ","
        end
        str = str .. "}"
    elseif type(value) == "string" then
        str = string.format("%s%q", str, value)
    else
        str = str .. tostring(value)
    end
    return str
end

local function getDeviceState()
    local devState = {}
    local d = luup.variable_get(MYSID, "DeviceState", myDevice) or ""
    if not d:match("^%s*$") then
        local f, msg
        D("Loading device state string %1", d)
        f, msg = loadstring("local " .. d .. " return ds")
        if f == nil then
            L("getDeviceState() error loading DeviceState (%1): %2", msg, d)
            devState = {}
        else
            devState = f()
        end
    end
    return devState
end

local function clearDeviceState()
    D("clearDeviceState()")
    luup.variable_set(MYSID, "DeviceState", "", myDevice)
end

local function updateDeviceState( devid, isOn, expire )
    D("updateDeviceState(%1,%2,%3)", devid, isOn, expire )
    local devState = getDeviceState()
    devid = tostring(devid)
    if devState[devid] == nil then devState[devid] = {} end
    if isOn then
        devState[devid].state = 1
        devState[devid].onTime = os.time()
        devState[devid].expire = expire
    else
        devState[devid].state = 0
        devState[devid].offTime = os.time()
        devState[devid].expire = nil
    end
    local json = require("dkjson")
    luup.variable_set(MYSID, "DeviceState", save("ds", devState), myDevice)
    return devState
end

-- Return true if a specified scene has been run (i.e. on the list)
local function isSceneOn(spec)
    local stateList = luup.variable_get(MYSID, "ScenesRunning", myDevice) or ""
    for i in string.gfind(stateList, "[^,]+") do
        if (i == spec) then return true end
    end
    return false
end

local function clearSceneState()
    D("clearSceneState()")
    luup.variable_set(MYSID, "ScenesRunning", "", myDevice)
end

-- Mark or unmark a scene as having been run
local function updateSceneState(spec, isOn)
    local stateList = luup.variable_get(MYSID, "ScenesRunning", myDevice) or ""
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
    for i,_ in pairs(t) do stateList = stateList .. "," .. tostring(i) end
    luup.variable_set(MYSID, "ScenesRunning", string.sub(stateList, 2, -1), myDevice)
end

-- Run "final" scene, if defined. This scene is run after all other targets have been
-- turned off.
local function runFinalScene()
    local scene  = getVarNumeric("FinalScene", nil)
    if (scene ~= nil) then
        D("runFinalScene(): running final scene %1", scene)
        luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=scene }, 0)
    end
end

-- Get the list of targets from our device state, parse to table of targets.
local function getTargetList()
    local s = luup.variable_get(MYSID, "Devices", myDevice) or ""
    return split(s)
end

-- Remove a target from the target list. Used when the target no longer exists. Linear, poor, but short list and rarely used.
local function removeTarget(target, tlist)
    if tlist == nil then tlist = getTargetList() end
    target = tostring(target)
    local i, d
    for i,d in ipairs(tlist) do
        local l = string.find(d, '[=<]')
        local devid = d
        if l ~= nil then devid = devid:sub(1,l-1) end
        if devid == target then
            table.remove(tlist, i)
            luup.variable_set(MYSID, "Devices", table.concat(tlist, ","), myDevice)
            return true
        end
    end
    return false
end

-- Light on or off? Returns boolean
local function isDeviceOn(targetid)
    local first = string.upper(string.sub(targetid, 1, 1))
    if first == "S" then
        D("isDeviceOn(): handling scene spec %1", targetid)
        return isSceneOn(targetid)
    end

    -- Handle as switch or dimmer
    D("isDeviceOn(): handling target spec %1", targetid)
    local r = tonumber(string.match(targetid, '^%d+'), 10)
    local val = "0"
    if luup.devices[r] ~= nil then
        if luup.device_supports_service(DIMMER_SID, r) then
            val = luup.variable_get(DIMMER_SID, "LoadLevelStatus", r)
        elseif luup.device_supports_service(SWITCH_SID, r) then
            val =  luup.variable_get(SWITCH_SID, "Status", r)
        end
    else
        L("isDeviceOn(): target spec " .. tostring(targetid) .. ", device " .. tostring(r) .. " not found in luup.devices")
        removeTarget(targetid)
        return nil
    end
    return val ~= "0"
end

-- Control target. Target is a string, expected to be a pure integer (in which case the target is assumed to be a switch or dimmer),
-- or a string in the form Sxx:yy, in which case xx is an "on" scene to run, and yy is an "off" scene to run.
local function targetControl(targetid, turnOn)
    D("targetControl(): targetid=%1, turnOn=%2", targetid, turnOn)
    local first = string.upper(string.sub(targetid, 1, 1))
    if first == "S" then
        D("targetControl(): handling as scene spec %1", targetid)
        i, j, onScene, offScene = string.find(string.sub(targetid, 2), "(%d+)-(%d+)")
        if i == nil then
            L("DeusExMachina:targetControl(): malformed scene spec=" .. tostring(targetid))
            return
        end
        onScene = tonumber(onScene, 10)
        offScene = tonumber(offScene, 10)
        if luup.scenes[onScene] == nil or luup.scenes[offScene] == nil then
            -- Both on scene and off scene must exist (defensive).
            L("targetControl(): one or both of the scenes in " .. tostring(targetid) .. " not found in luup.scenes!")
            removeTarget(targetid)
            return
        end
        D("targetControl(): on scene is %1, off scene is %2", onScene, offScene)
        local targetScene
        if turnOn then targetScene = onScene else targetScene = offScene end
        luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "RunScene", { SceneNum=targetScene }, 0)
        updateSceneState(targetid, turnOn)
    else
        -- Parse the level if this is a dimming target spec
        local lvl = 100
        local maxOnTime = nil
        local m = string.find(targetid, '<')
        if m ~= nil then 
            maxOnTime = string.sub(targetid, m+1)
            targetid = string.sub(targetid, 1, m-1)
        end
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
            L("targetControl(): device " .. tostring(targetid) .. " not found in luup.devices")
            removeTarget(targetid)
            return
        end
        if luup.device_supports_service("urn:upnp-org:serviceId:VSwitch1", targetid) then
            -- PHR 2017-08-14 pass newTargetValue as string for compat w/VSwitch (uses string comparisons in its implementation--needs an update)
            if turnOn then lvl = 1 end
            D("targetControl(): handling %1 (%3) as VSwitch, set target to %2", targetid, lvl, luup.devices[targetid].description)
            luup.call_action("urn:upnp-org:serviceId:VSwitch1", "SetTarget", {newTargetValue=tostring(lvl)}, targetid)
        elseif luup.device_supports_service(DIMMER_SID, targetid) then
            -- Handle as Dimming1
            D("targetControl(): handling %1 (%3) as generic dimmmer, set load level to %2", targetid, lvl, luup.devices[targetid].description)
            luup.call_action(DIMMER_SID, "SetLoadLevelTarget", {newLoadlevelTarget=lvl}, targetid) -- note odd case inconsistency
        elseif luup.device_supports_service(SWITCH_SID, targetid) then
            -- Handle as SwitchPower1
            if turnOn then lvl = 1 end
            D("targetControl(): handling %1 (%3) as generic switch, set target to %2", targetid, lvl, luup.devices[targetid].description)
            luup.call_action(SWITCH_SID, "SetTarget", {newTargetValue=lvl}, targetid)
        else
            L("targetControl(): don't know how to control target " .. tostring(targetid))
            removeTarget(targetid)
            return
        end
        local expire = nil
        if maxOnTime ~= nil then expire = os.time() + tonumber(maxOnTime,10)*60 end
        updateDeviceState(targetid, turnOn, expire)
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
            if devOn ~= nil and devOn then
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
    local dev,info
    local devState = getDeviceState()
    for dev,info in pairs(devState) do
        if info.expire ~= nil and info.expire <= os.time() then
            D("deusStep(): turning off time-limited device %1 (expired %2 ago)", dev, os.time()-info.expire)
            targetControl(dev, false)
            return true
        end
    end
    return false
end

-- Turn off all lights as fast as we can. Transition through SHUTDOWN state during,
-- in case user has any triggers connected to that state. The caller must immediately
-- set the next state when this function returns (expected would be STANDBY or IDLE).
local function clearLights()
    D("clearLights()")
    local devs, count
    devs, count = getTargetList()
    luup.variable_set(MYSID, "State", STATE_SHUTDOWN, myDevice)
    while count > 0 do
        targetControl(devs[count], false)
        count = count - 1
    end
    clearDeviceState()
    clearSceneState()
    runFinalScene()
end

local function checkLocation(dev)
    if luup.latitude == 0 and luup.longitude == 0 then
        setMessage("Invalid lat/long in system config", dev)
        error("Invalid lat/long/location data in system configuration.")
    end
end    

-- runOnce() looks to see if a core state variable exists; if not, a one-time initialization
-- takes place. For us, that means looking to see if an older version of Deus is still
-- installed, and copying its config into our new config. Then disable the old Deus.
local function runOnce()
    local s = luup.variable_get(MYSID, "Devices", myDevice)
    if (s == nil) then
        L("runOnce(): Devices variable not found, setting up new instance...")
        -- See if there are variables from older version of DEM
        -- Start by finding the old Deus device, if there is one...
        local devList = ""
        local i, olddev
        olddev = -1
        for i,v in pairs(luup.devices) do
            if (v.device_type == "urn:schemas-futzle-com:device:DeusExMachina:1") then
                L("runOnce(): Found old Deus Ex Machina device #" .. tostring(i))
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
                luup.variable_set(MYSID, "LightsOut", n, myDevice)
                deleteVar("LightsOutTime", myDevice)
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
                deleteVar("controlCount", myDevice)
            end

            -- Finally, turn off old Deus
            luup.call_action(oldsid, "SetEnabled", { NewEnabledValue = "0" }, olddev)
        end
        luup.variable_set(MYSID, "Devices", devList, myDevice)

        -- Set up some other default config
        luup.variable_set(MYSID, "MinCycleDelay", "300", myDevice)
        luup.variable_set(MYSID, "MaxCycleDelay", "1800", myDevice)
        luup.variable_set(MYSID, "MinOffDelay", "60", myDevice)
        luup.variable_set(MYSID, "MaxOffDelay", "300", myDevice)
        luup.variable_set(MYSID, "StartTime", "", myDevice)
        luup.variable_set(MYSID, "LightsOut", 1439, myDevice)
        luup.variable_set(MYSID, "MaxTargetsOn", 0, myDevice)
        luup.variable_set(MYSID, "LeaveLightsOn", 0, myDevice)
        luup.variable_set(MYSID, "Enabled", "0", myDevice)
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, myDevice)
        luup.variable_set(SWITCH_SID, "Status", "0", myDevice)
        luup.variable_set(SWITCH_SID, "Target", "0", myDevice)
    end

    -- Consider per-version changes.
    s = getVarNumeric("Version", 0)
    if (s < 20300) then
        -- v2.3: LightsOutTime (in milliseconds) deprecated, now using LightsOut (in minutes since midnight)
        L("runOnce(): updating config, version " .. tostring(s) .. " < 20300")
        s = luup.variable_get(MYSID, "LightsOut", myDevice)
        if (s == nil) then
            s = getVarNumeric("LightsOutTime") -- get pre-2.3 variable
            if (s == nil) then
                luup.variable_set(MYSID, "LightsOut", 1439, myDevice) -- default 23:59
            else
                luup.variable_set(MYSID, "LightsOut", tonumber(s,10) / 60000, myDevice) -- conv ms to minutes
            end
        end
        deleteVar("LightsOutTime", myDevice)
    end
    if (s < 20400) then
        -- v2.4: SwitchPower1 variables added. Follow previous plugin state in case of auto-update.
        L("runOnce(): updating config, version " .. tostring(s) .. " < 20400")
        luup.variable_set(MYSID, "MaxTargetsOn", 0, myDevice)
        local e = getVarNumeric("Enabled", 0)
        luup.variable_set(SWITCH_SID, "Target", e, myDevice)
        luup.variable_set(SWITCH_SID, "Status", 0, myDevice)
    end
    if s < 20500 then
        -- v2.5: Added StartTime and LeaveLightsOn
        L("runOnce(): updating config, version " .. tostring(s) .. " < 20500")
        luup.variable_set(MYSID, "StartTime", "", myDevice)
        luup.variable_set(MYSID, "LeaveLightsOn", 0, myDevice)
    end
    
    -- Update version state last.
    if (s ~= _CONFIGVERSION) then
        luup.variable_set(MYSID, "Version", _CONFIGVERSION, myDevice)
    end
end

-- Return the plugin version string
function getVersion()
    return _PLUGIN_VERSION, _CONFIGVERSION
end

-- Start stepper running. Note that we don't change state here. The intention is that Deus continues
-- in its saved operating state. 
local function deusStart(pdev)
    -- Immediately set a new timestamp
    runStamp = os.time()

    luup.call_delay("deusStep", 5, runStamp)
    D("deusStart(): scheduled first step, done")
end

-- Enable DEM by setting a new cycle stamp and scheduling our first cycle step.
function deusEnable(dev)
    L("enabling %1", dev)
    assert(dev == myDevice)
    
    luup.variable_set(SWITCH_SID, "Target", "1", dev)

    checkLocation(dev)
    
    setMessage("Enabling...", dev)

    -- Old Enabled variable follows SwitchPower1's Target
    luup.variable_set(MYSID, "Enabled", "1", dev)
    luup.variable_set(MYSID, "State", STATE_IDLE, dev)

    -- Launch the stepper. It will figure everything else out.
    deusStart(dev)

    -- SwitchPower1 status now on, we are running.
    luup.variable_set(SWITCH_SID, "Status", "1", dev)
end

-- Disable DEM and go to standby state. If we are currently cycling (as opposed to idle/waiting for sunset),
-- turn off any controlled lights that are on.
function deusDisable(dev)
    L("disabling %1", dev)
    -- assert(dev == myDevice)
    
    luup.variable_set(SWITCH_SID, "Target", "0", dev)

    setMessage("Disabling...", dev)
    
    -- Destroy runStamp so any running stepper exits when triggered (delay expires).
    runStamp = 0

    -- If current state is cycling or shutting down, rush that function (turn everything off)
    local s = getVarNumeric("State", STATE_STANDBY, dev)
    if ( s == STATE_CYCLE or s == STATE_SHUTDOWN ) then
        local leaveOn = getVarNumeric("LeaveLightsOn", 0)
        if leaveOn == 0 then
            clearLights()
        end
    end

    -- start with a clean slate next time
    clearDeviceState()
    clearSceneState()
    luup.variable_set(MYSID, "State", STATE_STANDBY, dev)
    luup.variable_set(MYSID, "Enabled", "0", dev)
    luup.variable_set(SWITCH_SID, "Status", "0", dev)

    setMessage("Disabled")
end

function setTrace(dev, newTraceState)
    L("setTrace(%1,%2)", dev, newTraceState)
    debugMode = newTraceState
    local n
    if newTraceState then n=1 else n=0 end
    luup.variable_set(MYSID, "DebugMode", n, dev)
    luup.variable_set(MYSID, "TraceMode", n, dev)
    L("setTrace() set state to %1 by action", newTraceState)
end

-- Initialize.
function deusInit(pdev)
    L("deusInit(%1) version %2", pdev, _PLUGIN_VERSION)

    if myDevice ~= 0 then
        setMessage("Another Deus is running!", pdev)
        return false
    end
    
    myDevice = pdev
    runStamp = 0

    checkLocation(pdev)
    
    setMessage("Initializing...")
    
    if debugMode then
        local status, body, httpStatus
        status, body, httpStatus = luup.inet.wget("http://127.0.0.1:3480/data_request?id=status&DeviceNum=" .. tostring(myDevice) .. "&output_format=json")
        D("deusInit(): status %2, startup state is %1", body, status)
    end

    -- Check for ALTUI and OpenLuup
    local k,v
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" then
            local rc,rs,jj,ra
            D("deusInit() detected ALTUI at %1", k)
            isALTUI = true
            rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin", 
                { newDeviceType=MYTYPE, newScriptFile="J_DeusExMachinaII1_ALTUI.js", newDeviceDrawFunc="DeusExMachina_ALTUI.DeviceDraw" }, 
                k )
            D("deusInit() ALTUI's RegisterPlugin action returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra)
        elseif v.device_type == "openLuup" then
            D("deusInit() detected openLuup")
            isOpenLuup = true
        end
    end

    -- Check UI version
    checkVersion(pdev)
    
    -- One-time stuff
    runOnce(pdev)
    
    -- Other initialization
    v = luup.variable_get(MYSID, "DebugMode", pdev)
    if v ~= nil then
        k = tonumber(v,10)
        if k ~= nil then debugMode = k ~= 0 
        else debugMode = string.len(v) > 0 
        end
    end

    -- Start up if we're enabled
    deusStart(pdev)
end

-- Run a cycle. If we're in "bedtime" (i.e. not between our cycle period between sunset and stop),
-- then we'll shut off any lights we've turned on and queue another run for the next sunset. Otherwise,
-- we'll toggled one of our controlled lights, and queue (random delay, but soon) for another cycle.
-- The shutdown of lights also occurs randomly, but can (through device state/config) have different
-- delays, so the lights going off looks more "natural" (i.e. not all at once just slamming off).
function deusStep(stepStampCheck)
    local stepStamp = tonumber(stepStampCheck)
    L("deusStep(): wakeup, stamp " .. tostring(stepStampCheck) .. ", device=" .. tostring(myDevice))
    if (stepStamp ~= runStamp) then
        L("deusStep(): stamp mismatch, another thread running. Bye!")
        return
    end
    if not isEnabled() then
        -- Not enabled, so force standby and stop what we're doing.
        L("deusStep(): not enabled, no more work for this thread...")
        luup.variable_set(MYSID, "State", STATE_STANDBY, myDevice)
        setMessage("")
        return
    end

    -- Get next sunset as seconds since midnight (approx), and true start time (configured or sunset)
    local sunset = getSunset()
    local nextStart, startWord 
    nextStart, startWord = startTime( myDevice )
    
    local currentState = getVarNumeric("State", STATE_STANDBY)
    if (currentState == STATE_STANDBY or currentState == STATE_IDLE) then
        D("deusStep(): step in state %1, lightsout=%2, sunset=%3, nextStart=%5, os.time=%4", currentState,
            luup.variable_get(MYSID, "LightsOut", myDevice), sunset, os.time(), nextStart)
        D("deusStep(): luup variables longitude=%1, latitude=%2, timezone=%3, city=%4, sunset=%5, version=%6",
            luup.longitude, luup.latitude, luup.timezone, luup.city, luup.sunset(), luup.version)
    end

    local inActiveTimePeriod = true
    if (isBedtime() ~= 0) then
        D("deusStep(): in lights out time")
        inActiveTimePeriod = false
    end
    
    -- Get going...
    local nextCycleDelay = 300 -- a default value to keep us out of hot water
    if currentState == STATE_IDLE and not inActiveTimePeriod then
        -- IDLE and not in active time period, probably a Luup restart. Wait for active period.
        L("deusStep(): IDLE and waiting for %1...", startWord)
        nextCycleDelay = nextStart - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
        luup.variable_set(MYSID, "State", STATE_IDLE, myDevice)
        setMessage("Waiting for " .. startWord)
    elseif not isActiveHouseMode() then
        -- Not in an active house mode. If we're not STANDBY or IDLE, turn everything back off and go to IDLE.
        if currentState == STATE_IDLE then
            L("deusStep(): IDLE in active period but inactive house mode; waiting for mode change.")
        else
            L("deusStep(): transitioning to IDLE, not in an active house mode.")
            local leaveOn = getVarNumeric("LeaveLightsOn", 0)
            if currentState ~= STATE_STANDBY then 
                if leaveOn == 0 then 
                    clearLights() 
                end
                luup.variable_set(MYSID, "State", STATE_IDLE, myDevice)
            end
        end

        -- Figure out how long to delay. If we're lights-out, delay to next start. Otherwise, short delay
        -- to re-check house mode, which could change at any time, so we must deal with it.
        if (inActiveTimePeriod) then
            nextCycleDelay = getRandomDelay("MinCycleDelay", "MaxCycleDelay")
            setMessage("Waiting for active house mode")
        else
            nextCycleDelay = nextStart - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
            setMessage("Idle until " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        end
    elseif not inActiveTimePeriod then
        -- Not in active period, but in active house mode and running state; shut things off...
        L("deusStep(): running off cycle, state=" .. tostring(currentState))
        luup.variable_set(MYSID, "State", STATE_SHUTDOWN, myDevice)
        if turnOffLimited() then
            nextCycleDelay = getVarNumeric("MinOffDelay", 60)
            setMessage("Shut-off cycle, next " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        elseif not turnOffLight() then
            -- No more lights to turn off
            runFinalScene()
            luup.variable_set(MYSID, "State", STATE_IDLE, myDevice)
            nextCycleDelay = nextStart - os.time() + getRandomDelay("MinCycleDelay", "MaxCycleDelay")
            L("DeusExMachina:deusStep(): all lights out; now IDLE, setting delay to restart cycling at %1", startWord)
            setMessage("Lights-out complete; waiting for " .. startWord)
        else
            nextCycleDelay = getRandomDelay("MinOffDelay", "MaxOffDelay", 60, 300)
            setMessage("Shut-off cycle, next " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
        end
    else
        -- Fully active. Find a random target to control and control it.
        L("deusStep(): running toggle cycle, state=" .. tostring(currentState))
        luup.variable_set(MYSID, "State", STATE_CYCLE, myDevice)
        nextCycleDelay = getRandomDelay("MinCycleDelay", "MaxCycleDelay")
        
        if not turnOffLimited() then
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
                            D("deusStep(): turn %1 OFF", devspec)
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
                                    D("deusStep(): too many targets on, max is %1, have %2, turning one off", maxOn, n)
                                    _, on, n = turnOffLight(on)
                                end
                            end
                            D("deusStep(): turn %1 ON", devspec)
                            targetControl(devspec, true)
                        end
                    end
                end
            end
        end

        -- If any devices are on limited on-time, we may need to adjust the cycle delay
        -- down so we don't miss its expiration. 
        local info
        local minOff = nil
        local devState = getDeviceState()
        for _,info in pairs(devState) do
            if info.expire ~= nil and (minOff == nil or info.expire < minOff) then
                minOff = info.expire
            end
        end
        if minOff ~= nil then
            local nextOff = minOff - os.time()
            if nextOff < 15 then nextOff = 15 end
            if nextOff < nextCycleDelay then
                D("deusStep() adjusting next cycle for time-limited device pending in %1", nextOff)
                nextCycleDelay = nextOff
            end
        end
        setMessage("Cycling; next " .. timeToString(os.date("*t", os.time() + nextCycleDelay)))
    end

    -- Arm for next cycle
    if nextCycleDelay ~= nil then
        L("deusStep(): cycle finished, next in " .. nextCycleDelay .. " seconds")
        if nextCycleDelay < 1 then nextCycleDelay = 60 end
        luup.call_delay("deusStep", nextCycleDelay, stepStamp)
    else
        L("deusStep(): nil nextCycleDelay, next cycle not scheduled!")
    end
end
