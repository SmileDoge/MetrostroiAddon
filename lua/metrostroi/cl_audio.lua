local bass_loaded, err_text = pcall(require, "bass")

Metrostroi.Audio = Metrostroi.Audio or {}

Metrostroi.Audio.Status = bass_loaded

Metrostroi.Audio.NeedPrecache = false
Metrostroi.Audio.PrecachedSamples = Metrostroi.Audio.PrecachedSamples or {}
Metrostroi.Audio.Channels = Metrostroi.Audio.Channels or {}

local FL = BASS.F

function Metrostroi.Audio.PrintError(str, ...)
    local name = debug.getinfo(2, "n").name or "NO NAME FUNC"
    local args = {...}

    if #args ~= 0 then str = Format(str, ...) end

    ErrorNoHaltWithStack("Metrostroi: AUDIO ERROR [" .. name .. "]: " .. str)
end

function Metrostroi.Audio.Print(str, ...)
    local name = debug.getinfo(2, "n").name or "NO NAME FUNC"
    local args = {...}

    if #args ~= 0 then str = Format(str, ...) end

    print("Metrostroi: AUDIO [" .. name .. "]: " .. str)
end

local function crc(str)
    return tonumber(util.CRC(str))
end

if bass_loaded then
    print("Metrostroi: Extended Audio enabled!")

    function Metrostroi.Audio.PrecacheSound(path, loop, flags)

        if not string.StartWith(path, "sound/") then path = "sound/" .. path end

        local path_crc = path

        if Metrostroi.Audio.PrecachedSamples[path_crc] then return end

        Metrostroi.Audio.Print("Precache sound '%s' %d", path_crc, #path_crc)

        if not flags then
            flags = bit.bor(FL.BASS_SAMPLE_3D, FL.BASS_SAMPLE_MONO)

            if loop then flags = bit.bor(FL.BASS_SAMPLE_3D, FL.BASS_SAMPLE_MONO, FL.BASS_SAMPLE_LOOP) end
        end
        
        local handle = BASS.SampleLoad(path_crc, flags)
        path_crc = string.Replace(path_crc, "\\", "/")
        
        if handle == nil then
            Metrostroi.Audio.PrintError("Sound not found! '%s'", path_crc)
            return
        end
        
        if handle ~= 0 then
            Metrostroi.Audio.PrecachedSamples[path_crc] = handle
            local info = BASS.SampleGetInfo(handle)
            info.max = 100
            BASS.SampleSetInfo(handle, info)

            PrintTable(BASS.SampleGetInfo(handle))

            return
        end

        local code = BASS.ErrorGetCode()

        Metrostroi.Audio.PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
    end

    local SOUND = {}

    function SOUND:PrintError(str, ...)
        local args = {...}

        if #args ~= 0 then str = Format(str, ...) end
        Metrostroi.Audio.PrintError("Sound: '%s'\n%s", self.path, str)
    end

    function SOUND:Play()
        local handle = self.handle

        local ret = BASS.ChannelPlay(handle, true)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SOUND:Pause()
        local handle = self.handle

        local ret = BASS.ChannelPause(handle)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SOUND:Stop()
        local handle = self.handle

        local ret = BASS.ChannelStop(handle)

        if not ret then
            local code = BASS.ErrorGetCode()
            if code == FL.BASS_ERROR_HANDLE then return ret end
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SOUND:Free(ignore)
        local handle = self.handle

        local ret = BASS.ChannelFree(handle)

        if not ret and not ignore then
            local code = BASS.ErrorGetCode()
            if code == FL.BASS_ERROR_HANDLE then return ret end
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        if not hide then Metrostroi.Audio.Channels[handle] = nil end

        return ret
    end
    function SOUND:SetVolume(volume)
        local handle = self.handle

        local ret = BASS.ChannelSetAttribute(handle, FL.BASS_ATTRIB_VOL, volume)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SOUND:GetVolume()
        local handle = self.handle

        local ret = BASS.ChannelGetAttribute(handle, FL.BASS_ATTRIB_VOL)

        if ret then
            return ret
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0
    end
    function SOUND:SetPitch(val)
        local handle = self.handle

        local ret = BASS.ChannelSetAttribute(handle, FL.BASS_ATTRIB_FREQ, 44100 * val)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SOUND:GetPitch()
        local handle = self.handle

        local ret = BASS.ChannelGetAttribute(handle, FL.BASS_ATTRIB_FREQ)

        if ret then
            return ret / 44100
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 1
    end
    function SOUND:SetPosition(pos, orient, vel)
        local handle = self.handle

        local ret = BASS.ChannelSet3DPosition(handle, pos, orient or vector_up, vel or vector_origin)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SOUND:GetPosition()
        local handle = self.handle

        local pos, orient, vel = BASS.ChannelGet3DPosition(handle)

        if pos then
            return pos, orient, vel
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return vector_origin, vector_origin, vector_origin
    end
    function SOUND:SetCone(iangle, oangle, outvol)
        local handle = self.handle

        local ret = BASS.ChannelSet3DAttributes(handle, -1, -1, -1, iangle, oangle, outvol)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SOUND:GetCone()
        local handle = self.handle

        local _, _, _, iangle, oangle, outvol = BASS.ChannelGet3DAttributes(handle)

        if iangle then
            return iangle, oangle, outvol
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0, 0, 0
    end
    function SOUND:SetDistance(min, max)
        local handle = self.handle

        local ret = BASS.ChannelSet3DAttributes(handle, -1, min, max, -1, -1, -1)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SOUND:GetDistance()
        local handle = self.handle

        local _, min, max = BASS.ChannelGet3DAttributes(handle)

        if min then
            return min, max
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0, 0
    end
    function SOUND:IsActive()
        local handle = self.handle

        local status = BASS.ChannelIsActive(handle)

        return status
    end
    function SOUND:IsValid()
        local handle = self.handle

        return not (BASS.ChannelIsActive(handle) == FL.BASS_ACTIVE_STOPPED)
    end
    function SOUND:__GC()
        if not self.isfree then self:Free(true) end
    end

    function Metrostroi.Audio.CreateSound(path_2, flags, hide, cb)
        local path = path_2

        if not string.StartWith(path, "sound/") then path = "sound/" .. path end

        local sample = Metrostroi.Audio.PrecachedSamples[path]
        cb = cb or function() end

        if not sample and not Metrostroi.Audio.NeedPrecache then
            Metrostroi.Audio.PrintError("Sound '%s' is not precached!", path)
            cb()
            return
        end

        if not sample and Metrostroi.Audio.NeedPrecache then
            --Metrostroi.Audio.PrecacheSound(path, true)
        end

        local chan = BASS.SampleGetChannel(sample, bit.bor(flags or 0, FL.BASS_SAMCHAN_NEW))

        if chan == 0 then
            local code = BASS.ErrorGetCode()
            Metrostroi.Audio.PrintError("Bass error [SampleGetChannel]: %d, %s", code, BASS.ErrorGetString(code))
            cb()
            return
        end

        local snd = setmetatable({path = path, handle = chan, isfree = false, hide = hide}, {__index = SOUND})
        
        local t = snd
        local proxy = newproxy(true)

        getmetatable(proxy).__gc = function(self) SOUND.__GC(t) end

        snd[proxy] = true

        if not hide then Metrostroi.Audio.Channels[chan] = snd end

        cb(snd)
        return snd
    end

    local SND = {}

    function SND:NotImplement()
        Metrostroi.Audio.PrintError("Not implement")
    end
    function SND:PrintError(str, ...)
        local args = {...}

        if #args ~= 0 then str = Format(str, ...) end
        Metrostroi.Audio.PrintError("Sound: '%s'\n%s", self.path, str)
    end

    function SND:EnableLooping(status)
        local handle = self.handle

        local ret = BASS.ChannelFlags(handle, status and FL.BASS_SAMPLE_LOOP or 0, FL.BASS_SAMPLE_LOOP)

        if ret ~= -1 then
            return true
        end
        
        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return false
    end -- todo
    function SND:FFT() self:NotImplement() end -- todo
    function SND:Get3DCone()
        local handle = self.handle

        local _, _, _, iangle, oangle, outvol = BASS.ChannelGet3DAttributes(handle)

        if iangle then
            return iangle, oangle, outvol
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0, 0, 0
    end
    function SND:Get3DEnabled() self:NotImplement() return true end -- todo
    function SND:Get3DFadeDistance()
        local handle = self.handle

        local _, min, max = BASS.ChannelGet3DAttributes(handle)

        if min then
            return min, max
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0, 0
    end
    function SND:GetAverageBitRate() self:NotImplement() return 0 end -- todo
    function SND:GetBitsPerSample() self:NotImplement() return 16 end -- todo
    function SND:GetFileName() self:NotImplement() return "" end -- todo
    function SND:GetLength() self:NotImplement() return 0 end -- todo
    function SND:GetLevel() self:NotImplement() return 0, 0 end -- todo
    function SND:GetPan() self:NotImplement() return 0 end -- todo
    function SND:GetPlaybackRate()
        local handle = self.handle

        local ret = BASS.ChannelGetAttribute(handle, FL.BASS_ATTRIB_FREQ)

        if ret then
            return ret / 44100
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 1
    end
    function SND:GetPos()
        local handle = self.handle

        local pos, orient, vel = BASS.ChannelGet3DPosition(handle)

        if pos then
            return pos, orient, vel
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return vector_origin, vector_origin, vector_origin
    end
    function SND:GetSamplingRate() self:NotImplement() return 44100 end
    local remap = {
        [0] = 0,
        [1] = 1,
        [2] = 3,
        [3] = 2,
    }
    function SND:GetState()
        local handle = self.handle

        local status = BASS.ChannelIsActive(handle)

        return remap[status] or status
    end
    function SND:GetTagsHTTP() self:NotImplement() return "" end -- todo
    function SND:GetTagsID3() self:NotImplement() return "" end -- todo
    function SND:GetTagsMeta() self:NotImplement() return "" end -- todo
    function SND:GetTagsOGG() self:NotImplement() return "" end -- todo
    function SND:GetTagsVendor() self:NotImplement() return "" end -- todo
    function SND:GetTime()
        local handle = self.handle

        local pos = BASS.ChannelGetPosition(handle, 0)

        if pos ~= -1 then
            return BASS.ChannelBytes2Seconds(handle, pos)
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0
    end
    function SND:GetVolume()
        local handle = self.handle

        local ret = BASS.ChannelGetAttribute(handle, FL.BASS_ATTRIB_VOL)

        if ret then
            return ret
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return 0
    end
    function SND:Is3D() self:NotImplement() return true end -- todo
    function SND:IsBlockStreamed() self:NotImplement() return false end -- todo
    function SND:IsLooping()
        local handle = self.handle

        local ret = BASS.ChannelFlags(handle, 0, 0)

        if ret ~= -1 then
            return bit.band(ret, FL.BASS_SAMPLE_LOOP)
        end
        
        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return false
    end -- todo
    function SND:IsOnline() self:NotImplement() return true end -- todo
    function SND:IsValid() 
        return self:GetState() ~= 0
    end
    function SND:Pause()
        local handle = self.handle

        local ret = BASS.ChannelPause(handle)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SND:Play()
        local handle = self.handle

        local ret = BASS.ChannelPlay(handle, false)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SND:Set3DCone(iangle, oangle, outvol)
        local handle = self.handle

        local ret = BASS.ChannelSet3DAttributes(handle, -1, -1, -1, iangle, oangle, outvol)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SND:Set3DFadeDistance(min, max)
        local handle = self.handle

        local ret = BASS.ChannelSet3DAttributes(handle, -1, min, max, -1, -1, -1)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SND:SetPan() self:NotImplement() return end -- todo
    function SND:SetPlaybackRate(val)
        local handle = self.handle

        local ret = BASS.ChannelSetAttribute(handle, FL.BASS_ATTRIB_FREQ, 44100 * val)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SND:SetPos(pos, orient, vel)
        local handle = self.handle

        local ret = BASS.ChannelSet3DPosition(handle, pos, orient or vector_up, vel or vector_origin)
        
        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        else
            BASS.Apply3D()
        end

        return ret
    end
    function SND:SetTime(secs)
        local handle = self.handle

        local pos = BASS.ChannelSeconds2Bytes(handle, secs)

        if pos ~= -1 then
            return BASS.ChannelSetPosition(handle, pos, 0)
        end

        local code = BASS.ErrorGetCode()
        self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))

        return false
    end
    function SND:SetVolume(volume)
        local handle = self.handle

        local ret = BASS.ChannelSetAttribute(handle, FL.BASS_ATTRIB_VOL, volume)

        if not ret then
            local code = BASS.ErrorGetCode()
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        return ret
    end
    function SND:Stop()
        local handle = self.handle

        --Metrostroi.Audio.Channels[tostring(handle)] = nil

        local ret = BASS.ChannelStop(handle)

        if not ret then
            local code = BASS.ErrorGetCode()
            if code == FL.BASS_ERROR_HANDLE then return ret end
            self:PrintError("Bass error: %d, %s", code, BASS.ErrorGetString(code))
        end

        self.isfree = true

        return ret
    end
    function SND:__GC()
        if not self.isfree then self:Stop() end
    end

    function Metrostroi.Audio.CreateSoundOld(path_2, str_flags, cb)
        local path = path_2

        if not string.StartWith(path, "sound/") then path = "sound/" .. path end

        local sample = Metrostroi.Audio.PrecachedSamples[path]
        cb = cb or function() end

        if not sample and not Metrostroi.Audio.NeedPrecache then
            Metrostroi.Audio.PrintError("Sound '%s' is not precached!", path)
            cb(nil, -1, "BASS_ERROR_UNKNOWN")
            return
        end
        
        local flags = 0
        local toplay = true
        local enable3d = false

        if string.find(str_flags, "noplay") then
            toplay = false
        end
        if string.find(str_flags, "3d") then
            enable3d = true
        end
        --[[
        if string.find(str_flags, "mono") then
            -- SampleGetChannel dont support change mono
        end
        if string.find(str_flags, "noblock") then
            -- SampleGetChannel dont support noblock
        end
        ]]

        local chan = BASS.SampleGetChannel(sample, FL.BASS_SAMCHAN_NEW)

        if chan == 0 then
            local code = BASS.ErrorGetCode()
            Metrostroi.Audio.PrintError("Bass error [SampleGetChannel]: %d, %s", code, BASS.ErrorGetString(code))
            cb(nil, code, BASS.ErrorGetString(code))
            return
        end

        local snd = setmetatable({path = path, handle = chan, isfree = false, hide = hide}, {__index = SND})
        
        local t = snd
        local proxy = newproxy(true)

        getmetatable(proxy).__gc = function(self) SND.__GC(t) end

        snd[proxy] = true

        --if not hide then Metrostroi.Audio.Channels[tostring(chan)] = snd end

        if not enable3d then
            BASS.ChannelSet3DAttributes(chan, BASS_3DMODE_OFF, 0, 0, -1, -1, 0)
        end

        if toplay then
            snd:Play()
        else
            snd:Pause()
        end

        cb(snd)
    end

    timer.Create("Metrostroi-Audio-Free-Invalid-Channels", 10, 0, function()
        for k, v in pairs(Metrostroi.Audio.Channels) do
            if not v:IsValid() then
                if v.Stop then v:Stop() elseif v.Free then v:Free() end

                Metrostroi.Audio.Channels[k] = nil
            end
        end
    end)

    concommand.Add("metrostroi_audio_stopall", function()
        for k, v in pairs(Metrostroi.Audio.Channels) do
            if not v:IsValid() then continue end

            v:Stop()
        end
    end)

    concommand.Add("metrostroi_audio_clear_cache", function()
        for k, v in pairs(Metrostroi.Audio.PrecachedSamples) do
            BASS.SampleFree(v)

            Metrostroi.Audio.PrecachedSamples[k] = nil
        end
    end)

    local vel
    local ply = LocalPlayer()
    local easing = math.ease.OutQuart

    hook.Add("RenderScene", "Metrostoi-Audio-Update3D", function(pos, ang)
        if not IsValid(ply) then ply = LocalPlayer() end
        if not IsValid(ply) then return end

        if not vel then vel = ply:GetVelocity() end
        
        local newvel = ply:GetVelocity()
        
        if ply:InVehicle() then
            local veh = ply:GetVehicle()
            newvel = veh:GetVelocity()
            
            if IsValid(veh:GetParent()) then
                newvel = veh:GetParent():GetVelocity()
            end
        end
        
        local front = -ang:Forward()
        local up = ang:Up()

        vel = LerpVector(easing(FrameTime()), vel, newvel)

        BASS.Set3DPosition(pos, vel, front, up)
        BASS.Apply3D()
    end)
else
    print("Metrostroi: Extended Audio disabled!")

    function Metrostroi.Audio.PrecacheSound()
        -- Original bass dont have SampleLoad
    end

    function Metrostroi.Audio.CreateSound(path_2, str_flags, cb)
        return sound.PlayFile(path_2, str_flags, cb)
    end
end