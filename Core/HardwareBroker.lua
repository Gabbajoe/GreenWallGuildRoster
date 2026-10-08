-- Internal, bounded queue. Only the private chat adapter calls OnChatEnter.
local _, addon = ...
function addon.NewHardwareBroker(env)
    local queue, bytes, lastOwner, busy = {}, 0, nil, false
    local stats = { submitted = 0, failed = 0, expired = 0, rejected = 0, highWater = 0 }
    local self = {}
    local function remove(i)
        local item = table.remove(queue, i)
        bytes = bytes - #item.payload
        return item
    end
    local function callback(fn, ...)
        if fn then pcall(fn, ...) end
    end
    local function prune()
        for i = #queue, 1, -1 do
            if queue[i].expiresAt <= env.now() then
                remove(i)
                stats.expired = stats.expired + 1
            end
        end
    end
    function self.IsReady() return env.ready() end
    function self.Enqueue(owner, key, payload, options)
        options = options or {}
        prune()
        if type(owner) ~= 'string' or not env.installed(owner)
            or type(key) ~= 'string' or #key == 0 or #key > 64
            or type(payload) ~= 'string' or #payload == 0 or #payload > 120 then
            return false, 'arguments'
        end
        for _, field in ipairs({ 'validate', 'onSubmit', 'onFailure' }) do
            if options[field] ~= nil and type(options[field]) ~= 'function' then return false, 'callback' end
        end
        local ttl = options.ttl or 120
        if type(ttl) ~= 'number' or ttl ~= ttl or ttl <= 0 or ttl > 120 then return false, 'ttl' end
        local count = 0
        for _, item in ipairs(queue) do
            if item.owner == owner then
                count = count + 1
                if item.key == key then
                    return item.payload == payload, 'duplicate'
                end
            end
        end
        if #queue >= 64 or count >= 8 or bytes + #payload > 7680 then return false, 'bounds' end
        queue[#queue + 1] = { owner = owner, key = key, payload = payload,
            expiresAt = env.now() + ttl, options = options }
        bytes = bytes + #payload
        stats.highWater = math.max(stats.highWater, #queue)
        return true
    end
    function self.Cancel(owner, key)
        for i = #queue, 1, -1 do
            if queue[i].owner == owner and (key == nil or queue[i].key == key) then remove(i) end
        end
    end
    function self.Clear()
        queue, bytes = {}, 0
    end
    function self.Pending(owner)
        prune()
        local count = 0
        for _, item in ipairs(queue) do if not owner or item.owner == owner then count = count + 1 end end
        return count
    end
    function self.Status()
        prune()
        local result = { depth = #queue, bytes = bytes, ready = self.IsReady() }
        for key, value in pairs(stats) do result[key] = value end
        return result
    end
    function self.OnChatEnter()
        if busy or not self.IsReady() then return end
        prune()
        local index = 1
        for i, item in ipairs(queue) do
            if item.owner ~= lastOwner then index = i; break end
        end
        if not queue[index] then return end
        local item = remove(index)
        busy = true
        local valid, allowed = true, true
        if item.options.validate then valid, allowed = pcall(item.options.validate) end
        if valid and allowed then
            lastOwner = item.owner
            stats.submitted = stats.submitted + 1
            callback(item.options.onSubmit)
            local ok, err = pcall(env.send, item.owner, item.payload)
            if not ok then
                stats.failed = stats.failed + 1
                callback(item.options.onFailure, err)
            end
        else
            stats.rejected = stats.rejected + 1
        end
        busy = false
    end
    return self
end
