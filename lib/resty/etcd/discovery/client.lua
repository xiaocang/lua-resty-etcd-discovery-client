local http = require "resty.http"
local cjson = require "cjson.safe"

local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local ngx_log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO
local w_count = ngx.worker.count
local w_id = ngx.worker.id
local ngx_sleep = ngx.sleep
local timer_at = ngx.timer.at
local encode_base64 = ngx.encode_base64

local fmod = math.fmod
local concat = table.concat
local pcall = pcall

local cjson_encode = cjson.encode
local cjson_decode = cjson.decode

local _M = { _VERSION = 0.1 }
local mt = { __index = _M }

local CONCURRENCY         = 10 -- default concurrency for test requests
local HTTP_TIMEOUT        = 3000 -- default http timeout option
local HTTP_VALID_STATUSES = { 200 } -- default http valid status

_M.WORKER_NUM  = 0
_M.ETCD_VERSION = "v3"
_M.ETCD_RETRIES = 3
_M.ETCD_TTL = 60

local _worker_etcd_session = {}

-- TODO: check ngx.config version

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end

local function request_json(hc, ...)
    local res, err = hc:request(...)

    if not res then
        hc:close()
        return nil, concat{"request failed: ", err}
    end

    local res_status = res.status
    local res_body = res.body
    hc:set_keepalive()

    if res_status ~= 200 then
        return nil, concat{"status code error: ", res_status}
    end

    local res_json = cjson_decode(res_body)
    if not res_json then
        return nil, concat{"malformed response body: ", res_body}
    end

    return res_json
end

function _M:add_service_list(opt)
    local typ = opt.type
    if not typ then
        return nil, "service list error: \"type\" is required"
    end

    local args = opt.args
    if not args then
        return nil, "service list error: \"args\" is required"
    elseif type(args) ~= 'table' then
        return nil, "service list error: \"args\" should be array"
    end

    local handler = opt.handler
    if not handler then
        return nil, "service list error: \"handler\" is required"
    elseif type(handler) ~= 'function' then
        return nil, "service list error: \"handler\" should be function"
    end

    local len = #self.service_list
    self.service_list[len + 1] = opt
end

function _M:add_http_service(etcd_opt, service_opt)
    -- required option check
    if not etcd_opt then
        return nil, "first parameter \"etcd_opt\" is required"
    end

    if not service_opt then
        return nil, "second parameter \"service_opt\" is required"
    end

    local etcd_service_key = etcd_opt.key
    if not etcd_service_key then
        return nil, "\"key\" is required"
    end

    local etcd_service_val = etcd_opt.val
    if not etcd_service_val then
        return nil, "\"val\" is required"
    end

    local http_params = service_opt.http_params
    if not http_params then
        return nil, "\"http_params\" is required"
    end

    local http_host = service_opt.host
    if not http_host then
        return nil, "\"host\" is required"
    end

    local http_port = service_opt.port
    if not http_port then
        return nil, "\"port\" is required"
    elseif type(http_port) ~= "number" then
        return nil, "\"port\" should be number"
    end

    -- optional args
    local http_timeout = service_opt.timeout or HTTP_TIMEOUT

    local http_valid_statuses
        = service_opt.valid_statuses or HTTP_VALID_STATUSES
    if type(http_valid_statuses) ~= "table" then
        return nil, "\"valid_statuses\" should be table"
    end

    local function _handler(_) -- discard args here, use upvalue instead
        local hc = http.new()
        hc:set_timeout(http_timeout)

        local ok, err = hc:connect(http_host, http_port)
        if not ok then
            return nil, err
        end

        local res, err = hc:request(http_params)
        if not res then
            hc:close()

            return nil, err
        end

        local res_status = res.status
        hc:set_keepalive()

        for _, valid_status in ipairs(http_valid_statuses) do
            if valid_status == res_status then
                return true
            end
        end

        return nil, "status code invalid"
    end

    return self:add_service_list {
        type = "http",
        args = {
            etcd_service_key = etcd_service_key,
            etcd_service_val = etcd_service_val
        },
        handler = _handler
    }
end

function _M.new(opt)
    local self = { opt = opt }

    -- bind to ngx_worker_id
    if fmod(w_id, w_count) ~= _M.WORKER_NUM then
        return
    end

    local service_list = {}
    self.service_list = service_list

    return setmetatable(self, mt)
end

local function _connect_etcd(opts, session)
    local _host, _port
    local function _hc()
        local hc = http.new()

        if _host and _port then
            local ok, err = hc:connect(_host, _port)

            if ok then
                return hc
            end
        end

        for _, opt in ipairs(opts) do
            local ok, err = hc:connect(opt.server, opt.port)

            if ok then
                _host, _port = opt.server, opt.port
                return hc
            end
        end

        return nil, "unable to connect etcd server"
    end

    local lease_id = session.lease_id
    if lease_id then -- renew lease
        local hc, err = _hc()
        if not hc then
            return nil, err
        end

        local ttl_uri = concat({
            "",
            _M.ETCD_VERSION,
            "lease",
            "timetolive"
        }, "/")

        local res_json, err = request_json(hc, {
            uri = ttl_uri,
            body = cjson_encode{
                ID = lease_id,
                keys = false
            }
        })

        local ttl = res_json.TTL
        local granted_ttl = res_json.grantedTTL

        if ttl > granted_ttl then
            session.lease_id = nil
        end
    end

    local lease_id = session.lease_id
    if not lease_id then-- grant lease
        local hc, err = _hc()
        if not hc then
            return nil, err
        end

        local grant_uri = concat({
            "",
            _M.ETCD_VERSION,
            "lease",
            "grant"
        }, "/")

        local res_json, err = request_json(hc, {
            uri = grant_uri,
            body = cjson_encode{
                ID = 0,
                TTL = _M.ETCD_TTL
            }
        })

        local res_error = res_json['error']
        if res_error and res_error ~= "" then
            return nil, concat{"etcd response error: ", res_error}
        end

        -- save to session
        session.lease_id  = res_json.ID
   end

    local function _req(http_opt)
        local hc, err = _hc()
        if not hc then
            return nil, err
        end

        -- add lease id
        local body = http_opt.body or {}
        body['lease'] = session.lease_id
        http_opt.body = cjson_encode(body)

        local res_json, err = request_json(hc, http_opt)

        local res_error = res_json['error']
        if res_error and res_error ~= "" then
            return nil, concat{"etcd response error: ", res_error}
        end
    end

    return {req = _req}
end

local function send_heartbeat(_sig, etcd_opt)
    local sig = _sig or "alive"

    local path = {"", _M.ETCD_VERSION, "kv"}
    local body = new_tab(0, 20)

    if sig == "alive" then -- renew lease
        path[#path + 1] = "put"

        body['key']   = encode_base64(etcd_opt.key)
        body['value'] = encode_base64(etcd_opt.value)
    elseif sig == "dead" then -- delete service key
        path[#path + 1] = "deleterange"

        body['key'] = encode_base64(etcd_opt.key)
    elseif sig == "unknown" then -- other status: do nothing
        return
    end

    local _etcd, err = _connect_etcd(etcd_opt, _worker_etcd_session)
    if not _etcd then
        ngx_log(ERR, "connect_etcd error: ", err)
        return
    end

    local retries = _M.ETCD_RETRIES

    for ix = 1, retries do
        local ok, err = _etcd:req {
            path = concat(path, "/"),
            body = body,
        }

        if ok then
            break
        end
    end

    if not ok then
        ngx_log(ERR, "etcd request failed: ", err)
        return
    end
end

local function spawn_handler(co_ctx, service_list)
    local serv_ix = co_ctx.ix
    co_ctx.ix = serv_ix + 1

    local serv_num = co_ctx.service_num
    if serv_ix > serv_num then
        return
    end

    local serv = service_list[serv_ix]
    local serv_type = serv.type
    local serv_handler = serv.handler

    if type(serv_handler) ~= "function" then
        return -1, "service_handler type error"
    end

    local ok, ret, err = pcall(serv_handler, serv.args)
    if not ok then
        return -2, concat{"handler \"", serv_type, "\" error: ", ret}
    end

    if not ret then
        return 1, concat{"service failed: ", err}
    end

    return 0
end

local function _timer(premature, self, spawn_opt)
    local spawn_interval    = spawn_opt.interval
    local spawn_concurrency = spawn_opt.concurrency or CONCURRENCY

    local service_list = self.service_list
    local service_num = #service_list

    local co_pool = new_tab(service_num, 0)
    local co_ctx = {
        ix = 1,
        service_num = service_num
    }
    for ix = 1, spawn_concurrency do
        co_pool[ix] = spawn(spawn_handler, co_ctx, service_list)
    end

    for ix = 1, spawn_concurrency do
        local ok, code, err = wait(co_pool[ix])

        local etcd_key = service_list[ix].args.etcd_service_key -- for log info

        -- TODO: add result to self object
        if not ok then
            ngx_log(ERR, etcd_key, ": something wrong happend.")
        elseif code < 0 then
            ngx_log(ERR, etcd_key,
                        ": something wrong happend in function: ", err)
        elseif code > 0 then
            ngx_log(ERR, etcd_key, ": test request failed.")
        elseif code == 0 then
            ngx_log(INFO, etcd_key, ": test request ok.")
        end
    end

    timer_at(spawn_interval, _timer, self, spawn_opt)
end

function _M:spawn_heartbeat(spawn_opt)
    if not spawn_opt then
        return nil, "first parameter \"spawn_opt\" is required"
    end

    local spawn_interval = spawn_opt.interval
    if not spawn_interval then
        return nil, "\"interval\" is required"
    elseif type(spawn_interval) == "number" then
        return nil, "\"interval\" should be number"
    end

    timer_at(0, _timer, self, spawn_opt)
end

return _M
