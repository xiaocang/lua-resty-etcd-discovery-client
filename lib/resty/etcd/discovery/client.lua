local spawn = ngx.thread.spawn
local wait = ngx.thread.wait
local ngx_log = ngx.log
local ERR = ngx.ERR
local INFO = ngx.INFO
local w_count = ngx.worker.count
local w_id = ngx.worker.id

local fmod = math.fmod
local concat = table.concat
local pcall = pcall

local _M = { _VERSION = 0.1 }
local mt = { __index = _M }

local CONCURRENCY = 10 -- default concurrency for test requests
local WORKER_NUM  = 0

-- TODO: check ngx.config version

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
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

    local http_req = service_opt.http_req
    if not http_req then
        return nil, "\"http_req\" is required"
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

    -- build ctx
    local ctx = new_tab(0, 20)

    -- TODO: http req handler
end

function _M.new(opt)
    local self = { opt = opt }

    -- bind to ngx_worker_id
    if fmod(w_id, w_count) ~= WORKER_NUM then
        return
    end

    return setmetatable(self, mt)
end

local function spawn_handler(co_ctx, service_list, services)
    local serv_ix = co_ctx.ix
    co_ctx.ix = serv_ix + 1

    local serv_num = co_ctx.service_num
    if serv_ix > serv_num then
        return
    end

    local serv = service_list[serv_ix]
    local serv_type = serv.type
    local serv_handler = services[serv_type]

    if type(serv_handler) ~= "function" then
        return -1, "service_handler type error"
    end

    local ok, ret, err = pcall(serv_handler, serv.opt)
    if not ok then
        return -2, concat{"handler \"", serv_type, "\" error: ", ret}
    end

    if not ret then
        return 1, "service failed"
    end

    return 0
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

    local spawn_concurrency = spawn_opt.concurrency or CONCURRENCY

    local service_list = self.service_list
    local service_num = #service_list
    local services = self.services or {}

    local co_pool = new_tab(service_num, 0)
    local co_ctx = {
        ix = 1,
        service_num = service_num
    }
    for ix = 1, spawn_concurrency do
        co_pool[ix] = spawn(spawn_handler, co_ctx, service_list, services)
    end

    for ix = 1, spawn_concurrency do
        local ok, code, err = wait(co_pool[ix])

        local etcd_key = service_list[ix].etcd_service_key -- for log info

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

    self:send_heartbeat()
end

function _M:send_heartbeat()
    -- TODO
end

return _M
