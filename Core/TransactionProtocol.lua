local ADDON_NAME, ns = ...

local Protocol = {}
local PREFIX = 'T1|'

local function validID(value)
    return type(value) == 'string' and #value >= 1 and #value <= 16
        and value:match('^[%w%-]+$') ~= nil
end

local function validKind(value)
    return value == 'full' or value == 'delta'
end

function Protocol.EncodeBegin(id, kind, chunkCount)
    if not validID(id) or not validKind(kind) then return nil end
    chunkCount = tonumber(chunkCount)
    if not chunkCount or chunkCount < 1 or chunkCount % 1 ~= 0 then return nil end
    return PREFIX .. 'B|' .. id .. '|' .. kind .. '|' .. chunkCount
end

function Protocol.EncodeData(id, index, payload)
    index = tonumber(index)
    if not validID(id) or not index or index < 1 or index % 1 ~= 0
        or type(payload) ~= 'string' or payload == '' then return nil end
    return PREFIX .. 'D|' .. id .. '|' .. index .. '|' .. payload
end

function Protocol.EncodeCommit(id)
    if not validID(id) then return nil end
    return PREFIX .. 'C|' .. id
end

function Protocol.Parse(message)
    if type(message) ~= 'string' or message:sub(1, #PREFIX) ~= PREFIX then return nil end
    local body = message:sub(#PREFIX + 1)
    local frameType, rest = body:match('^([BDC])|(.*)$')
    if frameType == 'B' then
        local id, kind, count = rest:match('^([^|]+)|([^|]+)|(%d+)$')
        count = tonumber(count)
        if not validID(id) or not validKind(kind) or not count then return false end
        return { type = frameType, id = id, kind = kind, count = count }
    elseif frameType == 'D' then
        local id, index, payload = rest:match('^([^|]+)|(%d+)|(.+)$')
        index = tonumber(index)
        if not validID(id) or not index or not payload then return false end
        return { type = frameType, id = id, index = index, payload = payload }
    elseif frameType == 'C' and validID(rest) then
        return { type = frameType, id = rest }
    end
    return false
end

function Protocol.NewOutbound(id, kind, chunks, now, options)
    options = options or {}
    local maxChunks = options.maxChunks or 32
    local maxBytes = options.maxBytes or 16384
    local ttl = options.ttl or 120
    if not validID(id) or not validKind(kind) or type(chunks) ~= 'table'
        or #chunks < 1 or #chunks > maxChunks then return nil, 'bounds' end
    local bytes, frozen = 0, {}
    for index, payload in ipairs(chunks) do
        if type(payload) ~= 'string' or payload == '' then return nil, 'payload' end
        bytes = bytes + #payload
        if bytes > maxBytes then return nil, 'bounds' end
        frozen[index] = payload
    end
    now = tonumber(now) or 0
    return {
        id = id, kind = kind, chunks = frozen, nextChunk = 1,
        createdAt = now, expiresAt = now + ttl, retryCount = 0,
        bytes = bytes,
        proposedCommitState = options.proposedCommitState,
    }
end

function Protocol.NewStager(options)
    options = options or {}
    local self = {
        transactions = {}, completed = {}, count = 0, bytes = 0,
        completedCount = 0,
        maxTransactions = options.maxTransactions or 16,
        maxCompleted = options.maxCompleted or 64,
        maxBytes = options.maxBytes or 32768,
        maxChunks = options.maxChunks or 32,
        maxPayloadBytes = options.maxPayloadBytes or 120,
        maxRowBytes = options.maxRowBytes or 220,
        ttl = options.ttl or 120,
    }

    local function remove(key)
        local tx = self.transactions[key]
        if not tx then return end
        self.bytes = self.bytes - tx.bytes
        self.count = self.count - 1
        self.transactions[key] = nil
    end

    function self:Prune(now)
        now = tonumber(now) or 0
        local expired = 0
        for key, tx in pairs(self.transactions) do
            if tx.expiresAt <= now then remove(key); expired = expired + 1 end
        end
        for key, expiresAt in pairs(self.completed) do
            if expiresAt <= now then
                self.completed[key] = nil
                self.completedCount = self.completedCount - 1
            end
        end
        return expired
    end

    function self:Reset()
        for key in pairs(self.transactions) do self.transactions[key] = nil end
        for key in pairs(self.completed) do self.completed[key] = nil end
        self.count, self.bytes, self.completedCount = 0, 0, 0
    end

    function self:Depth()
        return self.count, self.bytes
    end

    local function validatePayload(payload)
        if #payload > self.maxPayloadBytes then return false end
        for row in payload:gmatch('[^~]+') do
            local _, separators = row:gsub(';', '')
            if #row > self.maxRowBytes or separators ~= 7 then return false end
        end
        return true
    end

    local function rememberCompleted(key, expiresAt)
        if self.completed[key] then
            self.completed[key] = expiresAt
            return
        end
        if self.completedCount >= self.maxCompleted then
            local oldestKey, oldestExpiry
            for candidate, expiry in pairs(self.completed) do
                if not oldestExpiry or expiry < oldestExpiry then
                    oldestKey, oldestExpiry = candidate, expiry
                end
            end
            if oldestKey then
                self.completed[oldestKey] = nil
                self.completedCount = self.completedCount - 1
            end
        end
        self.completed[key] = expiresAt
        self.completedCount = self.completedCount + 1
    end

    local function complete(key, tx, now)
        if not tx.commitSeen or not tx.count or not tx.kind then return nil end
        for index = 1, tx.count do
            if not tx.chunks[index] then return nil end
        end
        local payload = table.concat(tx.chunks, '~')
        local result = { tag = tx.tag, sender = tx.sender, id = tx.id,
            kind = tx.kind, payload = payload }
        remove(key)
        rememberCompleted(key, now + self.ttl)
        return result
    end

    function self:Handle(tag, sender, message, now)
        now = tonumber(now) or 0
        self:Prune(now)
        local frame = Protocol.Parse(message)
        if frame == nil then return 'legacy' end
        if frame == false then return 'rejected', 'malformed' end
        local key = tostring(tag or '') .. '\031' .. tostring(sender or '') .. '\031' .. frame.id
        if self.completed[key] and self.completed[key] > now then return 'duplicate' end

        local tx = self.transactions[key]
        if not tx then
            if self.count >= self.maxTransactions then return 'rejected', 'transactions' end
            tx = { tag = tag, sender = sender, id = frame.id, chunks = {},
                bytes = 0, createdAt = now, expiresAt = now + self.ttl }
            self.transactions[key] = tx
            self.count = self.count + 1
        end
        tx.expiresAt = now + self.ttl

        if frame.type == 'B' then
            if frame.count < 1 or frame.count > self.maxChunks then
                remove(key); return 'rejected', 'chunks'
            end
            if (tx.count and tx.count ~= frame.count) or (tx.kind and tx.kind ~= frame.kind) then
                remove(key); return 'rejected', 'conflict'
            end
            tx.count, tx.kind = frame.count, frame.kind
            for index in pairs(tx.chunks) do
                if index > tx.count then remove(key); return 'rejected', 'index' end
            end
        elseif frame.type == 'D' then
            if frame.index < 1 or frame.index > self.maxChunks
                or (tx.count and frame.index > tx.count)
                or not validatePayload(frame.payload) then
                remove(key); return 'rejected', 'payload'
            end
            local existing = tx.chunks[frame.index]
            if existing and existing ~= frame.payload then
                remove(key); return 'rejected', 'conflict'
            elseif not existing then
                local nextBytes = self.bytes + #frame.payload
                if nextBytes > self.maxBytes then
                    remove(key); return 'rejected', 'bytes'
                end
                tx.chunks[frame.index] = frame.payload
                tx.bytes = tx.bytes + #frame.payload
                self.bytes = nextBytes
            end
        elseif frame.type == 'C' then
            tx.commitSeen = true
        end

        local result = complete(key, tx, now)
        if result then return 'committed', result end
        return 'staged'
    end

    return self
end

ns.TransactionProtocol = Protocol
