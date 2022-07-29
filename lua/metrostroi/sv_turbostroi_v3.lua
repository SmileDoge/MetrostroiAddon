--[[
- Turbostroi version 3
- LUA By: Smile
- DLL By: Smile and Vogel
- DLL Lang: Rust
- Github: 

- Docs:

---- Types
- i32 - signed integer 32 bits (4 bytes)
- i16 - signed integer 16 bits (2 bytes)
- i8  - signed integer 8  bits (1 bytes)
- u32 - unsigned integer 32 bits (4 bytes)
- u16 - unsigned integer 16 bits (2 bytes)
- u8  - unsigned integer 8  bits (1 bytes)
- f32 - float 32 bits (4 bytes)
- usize - unsigned size (on 32 bit = 4 bytes, on 64 bit = 8 bytes)

- function - lua function
- string - lua string
- Msg - msg structure
- void - lua nil
- error - lua error

------ GMOD LUA

---- Global Var 
- Turbostroi.Version -> string

---- Global Functions
--- From DLL
- Turbostroi.InitializeTrain(id: i32, code: string) -> void
- Turbostroi.DeinitializeTrain(id: i32) -> void
- Turbostroi.CreateMessage(size: usize) -> Msg or error
- Turbostroi.SendMessage(msg: Msg, target_id: i32) -> void
- Turbostroi.RecvMessage(target_id: i32) -> Msg or void : returns void if queue is empty
- Turbostroi.SetAffinityMask(mask: usize) -> void

--- From Lua

- Turbostroi.AddCustomMessageType(id: number, func: function) -> void : add custom type for receive message from thread

---- Structs

--- Msg 
-- Functions

- Note: Write and Read have auto clamp to Msg size

- Msg:WriteUInt8 (val: u8) -> void
- Msg:WriteUInt16(val: u16) -> void
- Msg:WriteUInt32(val: u32) -> void

- Msg:WriteInt8 (val: i8) -> void
- Msg:WriteInt16(val: i16) -> void
- Msg:WriteInt32(val: i32) -> void

- Msg:WriteFloat(val: f32) -> void

- Msg:ReadUInt8 () -> u8
- Msg:ReadUInt16() -> u16
- Msg:ReadUInt32() -> u32

- Msg:ReadInt8 () -> i8
- Msg:ReadInt16() -> i16
- Msg:ReadInt32() -> i32

- Msg:ReadFloat() -> f32

- Msg:WriteData(bytes: string) -> void : bytes can contain \0
- Msg:ReadData(len: i32) -> string

- Msg:Seek(pos: usize) -> void
- Msg:Tell() -> usize

------ TRAIN THREAD LUA

--- Global Var
- CONST: TURBOSTROI -> boolean (always true)
- CONST: TRAIN_ID -> number (entity id)

--- Global functions
- CreateMessage(size: usize) -> Msg or error
- SendMessage(msg: Msg) -> void
- RecvMessage() -> Msg or void
- SetAffinityMask(mask: usize) -> void

-------- Messages ID

----- TRAIN THREAD -> GMOD THREAD -----

--- 1 - Send systems variable changes
--- 2 - Send trigger input
--- 3 - Sound send
--- 4 - Send train wire changes

----- GMOD THREAD -> TRAIN THREAD -----

--- 1 - Send systems variable changes
--- 2 - Send trigger input
--- 4 - Send train wire changes

--- 100 - Print Message
--- 101 - Error Message
--- 102 - Set Affinity Mask
--- 103 - Send All Systems and Load Systems

--- 200 - Send LUA Code
]]--

if Turbostroi and not Turbostroi.Version then return end

if not TURBOSTROI then
    if Turbostroi.Version ~= "3.1.0" then return end

    local FPS = math.Round(1000*engine.TickInterval())

    TS_filesCache = TS_filesCache or {}
    TS_loadSystem = TS_loadSystem or {}
    TS_registeredSystem = TS_registeredSystem or {}
    TS_turbostroiTrains = TS_turbostroiTrains or {}
    TS_messageTypes = TS_messageTypes or {}
    -- local TS_filesCache = {}
    -- local TS_loadSystem = {}
    -- local TS_registeredSystem = {}
    -- local TS_turbostroiTrains = {}

    Turbostroi.SetFPSSimulation(FPS)

    Turbostroi.InternalInitializeTrain = Turbostroi.InternalInitializeTrain or Turbostroi.InitializeTrain
    Turbostroi.InternalDeinitializeTrain = Turbostroi.InternalDeinitializeTrain or Turbostroi.DeinitializeTrain

    local CreateMessage = Turbostroi.CreateMessage
    local SendMessage = Turbostroi.SendMessage
    local RecvMessage = Turbostroi.RecvMessage

    local temp_msg = Turbostroi.CreateMessage(1)

    temp_msg = nil

    local mt = debug.getregistry()["msgts"]
    
    local msg_readu8  = mt["ReadUInt8"]
    local msg_readu16 = mt["ReadUInt16"]
    local msg_readu32 = mt["ReadUInt32"]
    
    local msg_readi8  = mt["ReadUInt8"]
    local msg_readi16 = mt["ReadUInt16"]
    local msg_readi32 = mt["ReadUInt32"]

    local msg_readfloat = mt["ReadFloat"]
    local msg_readdata = mt["ReadData"]

    local msg_writeu8  = mt["WriteUInt8"]
    local msg_writeu16 = mt["WriteUInt16"]
    local msg_writeu32 = mt["WriteUInt32"]
    
    local msg_writei8  = mt["WriteInt8"]
    local msg_writei16 = mt["WriteInt16"]
    local msg_writei32 = mt["WriteInt32"]
    
    local msg_writefloat = mt["WriteFloat"]
    local msg_writedata = mt["WriteData"]

    local msg_seek = mt["Seek"]
    local msg_tell = mt["Tell"]

    local dataCache = {{}, {}}

    local cacheEnabled = CreateConVar("turbostroi_caching_enabled", "1", FCVAR_ARCHIVE, "Turbostroi file caching")
    local train_mask = CreateConVar("turbostroi_train_cores", "7", bit.bor(FCVAR_ARCHIVE,FCVAR_NEVER_AS_STRING) , "Train thread affinity mask")
    local srcds_mask = CreateConVar("turbostroi_main_cores", "8", bit.bor(FCVAR_ARCHIVE,FCVAR_NEVER_AS_STRING) , "Main server (srcds) thread affinity mask")

    local function printTurbostroi(str)
        print("Metrostroi: Turbostroi V3 - " .. str)
    end

    cvars.AddChangeCallback("turbostroi_train_cores", function(name, old, new)
        for k, v in pairs(TS_turbostroiTrains) do
            local affinity = CreateMessage(32)
            affinity:WriteUInt8(102)
            affinity:WriteUInt32(tonumber(new) or 7)
            SendMessage(affinity, k)
        end
    end)

    cvars.AddChangeCallback("turbostroi_main_cores", function(name, old, new)
        printTurbostroi("New affinity mask = " .. new)
        Turbostroi.SetAffinityMask(tonumber(new))
    end)
    Turbostroi.SetAffinityMask(srcds_mask:GetInt() or 8)

    concommand.Add("turbostroi_clear_cache", function(ply)
        if IsValid(ply) then return end
        TS_filesCache = {}
        printTurbostroi("Cache of loaded files cleared!")
    end)

    local function getFile(filename)
        if not TS_filesCache[filename] then
            local str = file.Read(filename, "LUA")

            if not str then
                error("Metrostroi: Turbostroi - File not found! ( " .. filename .. " )")
            end
            
            if cacheEnabled:GetBool() then
                TS_filesCache[filename] = {data = str, size = file.Size(filename, "LUA")}
            else
                return str, file.Size(filename, "LUA")
            end
        end

        return TS_filesCache[filename].data, TS_filesCache[filename].size
    end

    function Turbostroi.AddCustomMessageType(num, func)
        TS_messageTypes[num] = func
    end

    function Turbostroi.RegisterSystem(name, filename)
        TS_registeredSystem[name] = filename
        printTurbostroi("Register " .. name)
    end
    
    function Turbostroi.LoadSystem(sys_name, name)
        TS_loadSystem[name] = sys_name
    end

    function Turbostroi.TriggerInput(train,system,name,value)
        if type(value) == "boolean" then value = value and 1 or 0 end

        local msg = CreateMessage(512)

        local sys_len, name_len = #system, #name
        msg_writeu8(msg, 2)
        msg_writefloat(msg, value or 0)

        msg_writeu16(msg, sys_len)
        msg_writedata(msg, system)
        
        msg_writeu16(msg, name_len)
        msg_writedata(msg, name)

        SendMessage(msg, train:EntIndex())
    end

    local function loadSystems(msg)
        local all_systems_count = table.Count(TS_registeredSystem)

        msg:WriteUInt8(103)
        msg:WriteUInt16(all_systems_count)

        for k, v in pairs(TS_registeredSystem) do
            local code, size = getFile(v)
            local system_len, code_len = #v, size

            msg:WriteUInt16(system_len)
            msg:WriteData(v)

            msg:WriteUInt32(code_len)
            msg:WriteData(code)
        end

        local count = table.Count(TS_loadSystem)

        msg:WriteUInt16(count)

        for k, v in pairs(TS_loadSystem) do
            local name_len, sys_name_len = #k, #v
            
            msg:WriteUInt16(name_len)
            msg:WriteData(k)

            msg:WriteUInt32(sys_name_len)
            msg:WriteData(v)
        end

        TS_loadSystem = {}
    end

    local function loadFailsim(msg)
        local filename = "metrostroi/sh_failsim.lua"
        local failsim, failsim_size = getFile(filename)

        msg:WriteUInt8(200)
        msg:WriteUInt16(failsim_size)
        msg:WriteData(failsim)
        msg:WriteUInt16(#filename)
        msg:WriteData(filename)
    end

    function Turbostroi.InitializeTrain(self)
        local id = self:EntIndex()

        local code = getFile("metrostroi/sv_turbostroi_v3.lua")

        dataCache[id] = {wires = {}, systems = {}}

        for sys_name, sys in pairs(self.Systems) do
            if sys.DontAccelerateSimulation and sys.OutputsList then
                dataCache[id].systems[sys_name] = sys
                dataCache[id][sys_name] = {}
                for _, var_name in next, sys.OutputsList do
                    dataCache[id][sys_name][var_name] = 0
                end
            end
        end

        Turbostroi.InternalInitializeTrain(id, code)

        local failsim = CreateMessage(1024 * 1024) --- 1 MB
        loadFailsim(failsim)
        SendMessage(failsim, id)

        local msg = CreateMessage(8 * 1024 * 1024) --- 8 MB
        loadSystems(msg)
        SendMessage(msg, id)
        
        local affinity = CreateMessage(32)
        affinity:WriteUInt8(102)
        affinity:WriteUInt32(train_mask:GetInt() or 7)
        SendMessage(affinity, id)

        TS_turbostroiTrains[id] = true
    end

    function Turbostroi.DeinitializeTrain(self)
        local id = self:EntIndex()

        Turbostroi.InternalDeinitializeTrain(id)

        TS_turbostroiTrains[id] = nil 
    end

    local tableCount = table.Count
    local Entity = Entity
    local next = next
    local SysTime = SysTime
    local mathRound = math.Round
    local tableHasValue = table.HasValue
    local type = type

    local function turbostroiHandle1(train, msg)
        msg_readu16(msg)
        while true do
            local sys_len = msg_readu16(msg)
            if sys_len == 0 then break end
            local sys = msg_readdata(msg, sys_len)
            while true do
                local var_len = msg_readu16(msg)
                if var_len == 0 then break end
                local var = msg_readdata(msg, var_len)
                local val = msg_readfloat(msg)

                train.Systems[sys][var] = val

                if train.TriggerTurbostroiInput then train:TriggerTurbostroiInput(sys,var,val) end
            end
        end
    end

    local function turbostroiHandle2(train, msg)
        local val = msg_readfloat(msg)

        local sys_len = msg_readu16(msg)
        local sys = msg_readdata(msg, sys_len)

        local name_len = msg_readu16(msg)
        local name = msg_readdata(msg, name_len)

        train[sys]:TriggerInput(name, val)
    end

    local function turbostroiHandle3(train, msg)
        local range = msg_readfloat(msg)
        local pitch = msg_readfloat(msg)
        local id_len = msg_readu16(msg)
        local soundid = msg_readdata(msg, id_len)
        local loc_len = msg_readu16(msg)
        local location = msg_readdata(msg, loc_len)
        
        train:PlayOnce(soundid,location,range,pitch)
    end

    local function turbostroiHandle4(train, msg)
        local changes = msg_readu16(msg)

        for i=1, changes do
            local wire = msg_readfloat(msg)
            local val = msg_readfloat(msg)

            if not train.TrainWireWritersID[wire] then train.TrainWireWritersID[wire] = true end
            train.TrainWireTurbostroi[wire] = val
        end
    end
    
    local color_pink = Color(255, 0, 255)
    local color_red = Color(255, 0, 0)
    local color_blue = Color(0, 0, 255)

    local function turbostroiGetData(train, k)
        while true do
            local msg = RecvMessage(k)
            if not msg then break end

            local typ = msg_readu8(msg)

            if typ == 1 then
                turbostroiHandle1(train, msg)
            elseif typ == 2 then
                turbostroiHandle2(train, msg)
            elseif typ == 3 then
                turbostroiHandle3(train, msg)
            elseif typ == 4 then
                turbostroiHandle4(train, msg)
            elseif typ == 100 then
                local len = msg:ReadUInt16()
                local str = msg:ReadData(len)
                
                MsgC(color_pink, str, "\n")
            elseif typ == 101 then
                local len = msg:ReadUInt16()
                local str = msg:ReadData(len)
                
                MsgC(color_red, str, "\n")
            else
                if TS_messageTypes[typ] then
                    TS_messageTypes[typ](train, msg)
                else
                    MsgC(color_blue, "UNKNOWN MESSAGE TYPE '" .. typ .. "'")
                end
            end
        end
    end

    local msg_wire, was_sent_wire = nil, true
    local msg_sys, was_sent_sys = nil, true

    local function turbostroiSendWire(train, k, dataCacheTrain)
        local wire_changes_num = 0
        local wires_cache = dataCacheTrain["wires"]
        local wires = train.TrainWires

        for i in next, wires do
            local wire_val = wires[i] or 0
            if wires_cache[i] ~= wire_val then
                msg_writefloat(msg_wire, i)
                msg_writefloat(msg_wire, wire_val)
                
                wire_changes_num = wire_changes_num + 1
                wires_cache[i] = wire_val
            end
        end

        if wire_changes_num == 0 then return end

        was_sent_wire = true

        msg_writeu8(msg_wire, 0) -- end
        SendMessage(msg_wire, k)
    end


    local function turbostroiSendSys(train, k, dataCacheTrain)
        local systems_exists = {}

        local edited = false

        for sys_name, sys in next, dataCacheTrain.systems do
            for _, var_name in next, sys.OutputsList do
                local val = sys[var_name] or 0
                local typ = type(val)
                if typ == "boolean" then val = val and 1 or 0 end
                if typ == "number" then
                    if dataCacheTrain[sys_name][var_name] ~= val then
                        if not systems_exists[sys_name] then
                            systems_exists[sys_name] = true
                            edited = true
                            msg_writeu16(msg_sys, 0)
                            msg_writeu16(msg_sys, #sys_name)
                            msg_writedata(msg_sys, sys_name)
                        end

                        msg_writeu16(msg_sys, #var_name)
                        msg_writedata(msg_sys, var_name)
                        msg_writefloat(msg_sys, val)

                        dataCacheTrain[sys_name][var_name] = val
                    end
                end
            end
        end


        if not edited then return end

        was_sent_sys = true

        SendMessage(msg_sys, k)
    end

    local UpdateThink = Turbostroi.UpdateThink

    local function turbostroiThink()
        UpdateThink(SysTime())

        for k,v in next, TS_turbostroiTrains do
            local train = Entity(k)

            turbostroiGetData(train, k)

            local dataCacheTrain = dataCache[k]

            if was_sent_wire then
                msg_wire = CreateMessage(4096)
                msg_wire:WriteUInt8(4)
                was_sent_wire = false
            end
            
            turbostroiSendWire(train, k, dataCacheTrain)
            

            if was_sent_sys then
                msg_sys = CreateMessage(4096*2)
                msg_sys:WriteUInt8(1)
                was_sent_sys = false
            end

            turbostroiSendSys(train, k, dataCacheTrain)
        end
    end

    hook.Add("Think", "TurbostroiV3Think", turbostroiThink)
    
    return
end

local SendMessage = SendMessage
local CreateMessage = CreateMessage
local RecvMessage = RecvMessage

local CustomTypes = {}

function RegisterCustomType(num, func)
    CustomTypes[num] = func
end

do -- UTILS FUNCTIONS
    function print(...)
        local msg = CreateMessage(4096)
        local args = {...}
        local final = {}
        
        for k, v in pairs(args) do
            table.insert(final, tostring(v))
        end

        local fin = table.concat(final, "\t")

        msg:WriteUInt8(100)
        msg:WriteUInt16(#fin)
        msg:WriteData(fin)

        SendMessage(msg)
    end

    function printError(str)
        local msg = CreateMessage(4096)

        msg:WriteUInt8(101)
        msg:WriteUInt16(#str)
        msg:WriteData(str)

        SendMessage(msg)
    end

    function errorStack(add)
        local i = 1
        local str = ""
        while true do
            local info = debug.getinfo(i+(add or 0), "Sln")
            if not info then break end
    
            if info.what == "C" then
                str = str .. string.format("%s%d. %s - [C]:-1\n", string.rep(" ", i+1), i, info.name)
            else
                str = str .. string.format("%s%d. %s - %s:%d\n", string.rep(" ", i+1), i, info.name, info.short_src, info.currentline)
            end
            i = i + 1
        end
        return string.sub(str, 1, -2)
    end
    
    function errorHandler(err)
        printError(tostring(err) .. "\n" .. errorStack(2))
    end
end


xpcall(function()
    Metrostroi = {}
    Metrostroi.BaseSystems = {}
    Metrostroi.Systems = {}

    function Metrostroi.DefineSystem(name)
        TRAIN_SYSTEM = {}
        Metrostroi.BaseSystems[name] = TRAIN_SYSTEM

        -- Create constructor
        Metrostroi.Systems[name] = function(train,...)
            local tbl = { _base = name }
            local TRAIN_SYSTEM = Metrostroi.BaseSystems[tbl._base]
            if not TRAIN_SYSTEM then print("No system: "..tbl._base) return end
            for k,v in pairs(TRAIN_SYSTEM) do
                if type(v) == "function" then
                    tbl[k] = function(...)
                        if not Metrostroi.BaseSystems[tbl._base][k] then
                            print("ERROR",k,tbl._base)
                        end
                        return Metrostroi.BaseSystems[tbl._base][k](...)
                    end
                else
                    tbl[k] = v
                end
            end

            tbl.Initialize = tbl.Initialize or function() end
            tbl.Think = tbl.Think or function() end
            tbl.Inputs = tbl.Inputs or function() return {} end
            tbl.Outputs = tbl.Outputs or function() return {} end
            tbl.TriggerInput = tbl.TriggerInput or function() end
            tbl.TriggerOutput = tbl.TriggerOutput or function() end

            tbl.Train = train
            tbl:Initialize(...)
            tbl.OutputsList = tbl:Outputs()
            tbl.InputsList = tbl:Inputs()
            tbl.IsInput = {}
            for k,v in pairs(tbl.InputsList) do tbl.IsInput[v] = true end
            return tbl
        end
    end

    local dataCache = {wires = {}, wiresW = {}, wiresL = {}, no_accel = {}}

    LoadSystems = {}
    GlobalTrain = {}
    GlobalTrain.Systems = {}
    GlobalTrain.TrainWires = {}
    GlobalTrain.WriteTrainWires = {}

    
    function GlobalTrain.LoadSystem(self,a,b,...)
        local name
        local sys_name
        if b then
            name = b
            sys_name = a
        else
            name = a
            sys_name = a
        end

        if not Metrostroi.Systems[name] then print("Error: No system defined: "..name) return end
        if self.Systems[sys_name] then print("Error: System already defined: "..sys_name)  return end

        self[sys_name] = Metrostroi.Systems[name](self,...)
        self[sys_name].Name = sys_name
        self[sys_name].BaseName = name
        self.Systems[sys_name] = self[sys_name]

        -- Don't simulate on here
        local no_acceleration = Metrostroi.BaseSystems[name].DontAccelerateSimulation
        if no_acceleration then
            self.Systems[sys_name].Think = function() end
            self.Systems[sys_name].TriggerInput = function(train,name,value)
                local v = value or 0
                if type(value) == "boolean" then v = value and 1 or 0 end

                if not dataCache["no_accel"][sys_name] then dataCache["no_accel"][sys_name] = {} end

                if dataCache["no_accel"][sys_name][name] ~= value then
                    dataCache["no_accel"][sys_name][name] = value

                    local msg = CreateMessage(512)
            
                    local sys_len, name_len = #sys_name, #name
                    msg:WriteUInt8(2)
            
                    msg:WriteFloat(value)
                    
                    msg:WriteUInt16(sys_len)
                    msg:WriteData(sys_name)
            
                    msg:WriteUInt16(name_len)
                    msg:WriteData(name)
            
                    SendMessage(msg)
                end
                -- TS.ThreadSendMessage(_userdata, 4,sys_name,name,0,v)
                -- print("KEK")
            end
        elseif self[sys_name].OutputsList then
            dataCache[sys_name] = {}
            for _,name in pairs(self[sys_name].OutputsList) do
                dataCache[sys_name][name] = 0
            end
        end
    end
    
    function GlobalTrain.PlayOnce(self,soundid,location,range,pitch)
        local msg = CreateMessage(256)

        soundid = soundid or ""
        location = location or ""

        local id_len = #soundid
        local loc_len = #location

        msg:WriteUInt8(3)
        msg:WriteFloat(range or 0)
        msg:WriteFloat(pitch or 0)
        msg:WriteUInt16(id_len)
        msg:WriteData(soundid)
        msg:WriteUInt16(loc_len)
        msg:WriteData(location)

        SendMessage(msg)
    end

    function GlobalTrain.ReadTrainWire(self,n)
        return self.TrainWires[n] or 0
    end

    function GlobalTrain.WriteTrainWire(self,n,v)
        self.WriteTrainWires[n] = v
    end

    print("[! " .. TRAIN_ID .. "] Turbostroi V3 Train Initialize!")
    -- print("[! " .. TRAIN_ID .. "] Affinity Mask: " .. GetAffinityMask())

    _Time = 0

    function CurTime()
        return _Time
    end

    GlobalTrain.DeltaTime = 0.33

    function TrainThink(_, threadCurtime)
        CurrentTime = threadCurtime
        local self = GlobalTrain

        DataThink()

        if not self.Initialized then
            return
        end

        self.DeltaTime = (CurrentTime - self.PrevTime)
        self.PrevTime = CurrentTime


        if self.DeltaTime<=0 then return end

        _Time = _Time+self.DeltaTime


        for i,s in ipairs(self.Schedule) do
            for k,v in ipairs(s) do
                v:Think(self.DeltaTime / (v.SubIterations or 1),i)
            end
        end
    end

    local function tableCount(tbl)
        local n = 0
        for k, v in pairs(tbl) do n = n + 1 end
        return n
    end

    
    local msg_sys, was_sent_sys = nil, true

    
    local function turbostroiSendSys()
        local systems_exists = {}

        local edited = false
        for sys_name,system in pairs(GlobalTrain.Systems) do
            if system.OutputsList and (not system.DontAccelerateSimulation) then
                for _,name in pairs(system.OutputsList) do
                    local value = (system[name] or 0)
                    
                    if dataCache[sys_name][name] ~= value then
                        if not systems_exists[sys_name] then
                            systems_exists[sys_name] = {}
                            edited = true
                            msg_sys:WriteUInt16(0)
                            msg_sys:WriteUInt16(#sys_name)
                            msg_sys:WriteData(sys_name)
                        end
                        msg_sys:WriteUInt16(#name)
                        msg_sys:WriteData(name)
                        msg_sys:WriteFloat(value)
                        dataCache[sys_name][name] = value
                    end
                end
            end
        end

        if not edited then return end

        was_sent_sys = true

        SendMessage(msg_sys, k)
    end

    function DataThink()
        while true do
            local msg = RecvMessage()
            if not msg then break end

            local id = msg:ReadUInt8()

            if id == 1 then
                msg:ReadUInt16()
                while true do
                    local sys_len = msg:ReadUInt16()
                    if sys_len == 0 then break end
                    local sys = msg:ReadData(sys_len)
                    while true do
                        local var_len = msg:ReadUInt16()
                        if var_len == 0 then break end
                        local var = msg:ReadData(var_len)
                        local val = msg:ReadFloat()

                        local sys_tbl = GlobalTrain.Systems[sys]
                        
                        if sys_tbl then
                            GlobalTrain.Systems[sys][var] = val
                        end
                    end
                end
            elseif id == 2 then
                local val = msg:ReadFloat()

                local sys_len = msg:ReadUInt16()
                local sys = msg:ReadData(sys_len)

                local name_len = msg:ReadUInt16()
                local name = msg:ReadData(name_len)

                local sys_tbl = GlobalTrain.Systems[sys]

                if sys_tbl then
                    sys_tbl:TriggerInput(name,val)
                end
            elseif id == 4 then
                while true do
                    local wire = msg:ReadFloat()
                    if wire == 0 then break end
                    local val = msg:ReadFloat()
                    GlobalTrain.TrainWires[wire] = val
                end
            elseif id == 102 then
                local mask = msg:ReadUInt32()
                print("[! " .. TRAIN_ID .. "] Affinity Mask: " .. mask)
                SetAffinityMask(mask)
            elseif id == 103 then

                local all_system_count = msg:ReadUInt16()
                
                for i = 1, all_system_count do
                    local system_location_len = msg:ReadUInt16()
                    local system_location = msg:ReadData(system_location_len)

                    local system_code_len = msg:ReadUInt32()
                    local system_code = msg:ReadData(system_code_len)
                    xpcall(loadstring(system_code, system_location), function(err)
                        printError(tostring(err) .. "\n" .. errorStack(2))
                    end)
                end

                local load_system = msg:ReadUInt16()
                for i = 1, load_system do
                    local name_len = msg:ReadUInt16()
                    local name = msg:ReadData(name_len)

                    local sys_name_len = msg:ReadUInt32()
                    local sys_name = msg:ReadData(sys_name_len)

                    LoadSystems[sys_name] = name
                end

                Initialize()

            elseif id == 200 then

                local size = msg:ReadUInt16()

                local code = msg:ReadData(size)

                local src = "GMOD-LUA"
                local len = msg:ReadUInt16()
                if len != 0 then
                    src = msg:ReadData(len)
                end

                xpcall(loadstring(code, src), function(err)
                    printError(tostring(err) .. "\n" .. errorStack(2))
                end)
            else
                if CustomTypes[id] then
                    CustomTypes[id](msg)
                else
                    printError("UNKNOWN MESSAGE TYPE '" .. id .. "'")
                end
            end
        end

        do --- SYSTEM CHANGE SEND
            
            if was_sent_sys then
                msg_sys = CreateMessage(4096*2)
                msg_sys:WriteUInt8(1)
                was_sent_sys = false
            end

            turbostroiSendSys()
        end

        do --- WIRE CHANGE SEND
            local changes = {}
            local changes_num = 0

            for wire, val in pairs(GlobalTrain.WriteTrainWires) do
                if dataCache["wires"][wire] != val then
                    changes[wire] = val
                    changes_num = changes_num + 1
                    dataCache["wires"][wire] = val
                end
            end
            
            if changes_num > 0 then
                local msg = CreateMessage(4096)

                msg:WriteUInt8(4)
                msg:WriteUInt16(changes_num)

                for wire, val in pairs(changes) do
                    msg:WriteFloat(wire)
                    msg:WriteFloat(val)
                end

                SendMessage(msg)
            end
        end
    end

    function Initialize()
        print("[! " .. TRAIN_ID .. "] Loading systems")
        local time = SysTime()
        for k,v in pairs(LoadSystems) do
            GlobalTrain:LoadSystem(k,v)
        end
        print(string.format("[! " .. TRAIN_ID .. "] -Took %.0f ms",(SysTime()-time)*1000))
        GlobalTrain.PrevTime = CurrentTime
        local iterationsCount = 1
        if (not GlobalTrain.Schedule) or (iterationsCount ~= GlobalTrain.Schedule.IterationsCount) then
            GlobalTrain.Schedule = { IterationsCount = iterationsCount }
            local SystemIterations = {}
    
            -- Find max number of iterations
            local maxIterations = 0
            for k,v in pairs(GlobalTrain.Systems) do
                SystemIterations[k] = (v.SubIterations or 1)
                maxIterations = math.max(maxIterations,(v.SubIterations or 1))
            end
    
            -- Create a schedule of simulation
            for iteration=1,maxIterations do
                GlobalTrain.Schedule[iteration] = {}
                -- Populate schedule
                for k,v in pairs(GlobalTrain.Systems) do
                    if ((iteration)%(maxIterations/(v.SubIterations or 1))) == 0 then
                        table.insert(GlobalTrain.Schedule[iteration],v)
                    end
    
                end
            end
        end
        
        GlobalTrain.Initialized = true
    end
    
    function Think(gameCurtime, threadCurtime)
        xpcall(TrainThink, errorHandler, gameCurtime, threadCurtime)
    end
end, errorHandler)
