local _, ns = ...
local Protocol = ns.TransactionProtocol
local PassThrough = {}
ns.PassThrough = PassThrough

-- Pure state machine: Service and Echo only prepare/enqueue; the broker owns
-- the sole protected send. Snapshot state is frozen until the final echo.
function PassThrough.New(env)
    local self = { state = 'idle' }
    local active, serial, nextPrepare = nil, 0, 0
    local function count(key) env.stats[key] = (env.stats[key] or 0) + 1 end
    local function cancel()
        if active then active.broker.Cancel(env.owner, 'roster') end
    end
    function self.Abort(reason, delay)
        if active then
            cancel()
            env.abort(active.snapshot)
            active = nil
        end
        self.state = reason or 'idle'
        nextPrepare = env.now() + (delay or 0)
    end
    local function valid(tx)
        return active == tx and env.enabled() and env.tag() == tx.tag
            and env.valid(tx.snapshot) and env.capable() and env.now() < tx.expiresAt
            and env.broker() == tx.broker
    end
    local enqueue
    enqueue = function()
        local tx = active
        if not tx or tx.waiting then return end
        local payload = tx.frames[tx.index]
        local ok = tx.broker.Enqueue(env.owner, 'roster', payload, {
            ttl = math.max(0.01, tx.expiresAt - env.now()),
            validate = function()
                if valid(tx) then return true end
                self.Abort('invalidated', 30)
                return false
            end,
            onSubmit = function()
                tx.waiting, tx.sentAt = true, env.now()
                self.state = 'waiting-echo'
                count('passThroughSubmitted')
            end,
            onFailure = function()
                count('sendFailed')
                -- No send/retry here. Service may re-enqueue for a later Enter.
            end,
        })
        if ok then
            if not tx.queued then count('passThroughQueued') end
            tx.queued = true
            self.state = 'queued'
        else
            self.state = 'queue-full'
        end
    end
    function self.Service()
        if not env.enabled() then self.Abort('disabled'); return end
        local broker = env.broker()
        if not broker or broker.VERSION ~= 1 then self.Abort('broker-absent'); return end
        if active then
            if not valid(active) then
                local expired = env.now() >= active.expiresAt
                if expired then count('expired') end
                self.Abort(expired and 'expired' or 'invalidated', 30)
                return
            end
            if not broker.IsReady() then self.state = 'waiting-channel-or-broker'; return end
            if active.waiting then
                if env.now() - active.sentAt < 15 then return end
                if active.retries >= 2 then self.Abort('echo-timeout', 60); return end
                active.retries = active.retries + 1
                count('passThroughRetried')
                active.waiting, active.queued = false, false
            end
            enqueue()
            return
        end
        if env.now() < nextPrepare then return end
        if not broker.IsReady() then self.state = 'waiting-channel-or-broker'; return end
        if not env.capable() then self.state = 'waiting-capability'; return end
        local tag = env.tag()
        if not tag or not tag:match('^[%a%.]+$') or #tag > 16 then self.state = 'waiting-tag'; return end
        local snapshot = env.prepare(true)
        if not snapshot then self.state = 'waiting-roster'; return end
        serial = serial + 1
        local id = string.format('%x-%x', env.session(), serial)
        -- Bound the COMPLETE API payload, including tag, transaction header,
        -- index and separators, to 120 bytes (160 base64 bytes).
        local budget = 120 - #tag - 1 - #('T1|D|' .. id .. '|32|')
        local chunks, chunk = {}, ''
        for _, row in ipairs(snapshot.rows) do
            if #row > budget then
                env.abort(snapshot); self.state = 'oversized-row'; nextPrepare = env.now() + 600; return
            end
            if #chunk > 0 and #chunk + 1 + #row > budget then
                chunks[#chunks + 1], chunk = chunk, ''
            end
            chunk = chunk == '' and row or chunk .. '~' .. row
        end
        if chunk ~= '' then chunks[#chunks + 1] = chunk end
        local outbound = Protocol.NewOutbound(id, snapshot.kind, chunks, env.now(), { ttl = 120 })
        if not outbound then
            env.abort(snapshot); self.state = 'snapshot-bounds'; nextPrepare = env.now() + 600; return
        end
        local frames = { tag .. '#' .. Protocol.EncodeBegin(id, snapshot.kind, #chunks) }
        for i, data in ipairs(chunks) do frames[#frames + 1] = tag .. '#' .. Protocol.EncodeData(id, i, data) end
        frames[#frames + 1] = tag .. '#' .. Protocol.EncodeCommit(id)
        for _, payload in ipairs(frames) do
            if #payload > 120 then
                env.abort(snapshot); self.state = 'frame-bounds'; nextPrepare = env.now() + 600; return
            end
        end
        active = { snapshot = snapshot, tag = tag, broker = broker, frames = frames,
            index = 1, retries = 0, expiresAt = outbound.expiresAt }
        enqueue()
    end
    function self.Echo(message)
        local tx = active
        if not tx or not tx.sentAt or tx.frames[tx.index] ~= message then return false end
        if not valid(tx) then self.Abort('invalidated', 30); return false end
        cancel() -- also remove a timeout retry if its earlier echo arrived late
        count('passThroughEchoed')
        tx.index = tx.index + 1
        tx.waiting, tx.queued, tx.sentAt, tx.retries = false, false, nil, 0
        if tx.index > #tx.frames then
            if env.commit(tx.snapshot) then
                env.completed()
                active = nil
                self.state, nextPrepare = 'complete', env.now() + 600
            else self.Abort('invalidated', 30) end
        else enqueue() end
        return true
    end
    function self.Progress()
        local remaining = active and (#active.frames - active.index + 1) or 0
        local waiting = active and active.waiting or false
        return { state = self.state, remaining = math.max(0, remaining - (waiting and 1 or 0)),
            waiting = waiting, total = active and #active.frames or 0,
            seconds = active and math.max(0, math.ceil(active.expiresAt - env.now())) or 0 }
    end
    function self.Status()
        return self.state, active and active.index or 0, active and #active.frames or 0
    end
    return self
end
