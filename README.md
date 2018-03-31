Name
====

lua-resty-etcd-discovery-client - Etcd discovery client based on lua-resty-http

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Methods](#methods)
* [Installation](#installation)
* [TODO](#todo)
* [Author](#author)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

Status
======

This library is still under early development but is already production ready.

Synopsis
========

``` nginx
http {
    lua_package_path "/path/to/lua-resty-etcd-discovery-client/lib/?.lua;;"

    init_worker_by_lua {
        local etcd_client
            = require "resty.etcd.discovery.client"

        local etcd_server_opt = {
            { server = "10.0.1.10", port = 2379 },
            { server = "10.0.1.11", port = 2379 },
            { server = "10.0.1.12", port = 2379 }
        }
        local ec = etcd_client.new(etcd_server_opt)
        if not ec then
            -- bind to one ngx worker only to keep data share simple
            return
        end

        local service_discovery_opt = {
            key = "_openresty/demo_service",
            -- maybe use cjson.encode instead
            val = [=[
            {
                "name":"demo_service",
                "description": "other info"
            }
            ]=]
        }
        local http_service_opt = {
            host = "127.0.0.1", -- http service server addr
            port = 8080,        -- http service server port
            http_req = "GET /monitor HTTP/1.0\r\nHost: foo.com\r\n\r\n",
                        -- raw HTTP request for checking
            timeout = 1000,   -- 1 sec is the timeout for network operations
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
            valid_statuses = {200, 302},  -- a list valid HTTP status code
        }
        -- add new service
        ec:add_http_service(service_discovery_opt, http_service_opt)

        -- TODO
        --[[
        -- register new type of service
        ec:reg_service {
            type = "redis",
            callback = function(opt)
                opt = opt or {}

                local redis = require "resty.redis"
                red = redis.new()
                local ok, err = red:connect(opt.host, opt.port)
                red:close()

                return ok, err
            end
        }

        ec:add_custom_service({
            type = "redis",
            key = "_openresty/redis_server",
            val = '{"name":"redis_server"}'
        }, {
            host = "127.0.0.1",
            port = 6379
        })
        ]]--

        ec:spawn_heartbeat {
            interval = 20, -- run check cycle & send heartbeat every 20s
            concurrency = 10 -- concurrency level for test requests
        }

        -- server here
        server {
            listen 127.0.0.1:8080;

            location / {
            }

            location /monitor {
                return 200;
            }
        }
    }
}
```

Description
===========

This library performs etcd discovery client with healthcheck in NGINX.

[Back to TOC](#table-of-contents)
