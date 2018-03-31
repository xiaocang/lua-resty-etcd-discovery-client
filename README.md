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
* [Multiple Upstreams](#multiple-upstreams)
* [Installation](#installation)
* [TODO](#todo)
* [Bugs and Patches](#bugs-and-patches)
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
        local etcd_client = require "resty.etcd.discovery.client"

        local etcd_server_opt = {
            { server = "10.0.1.10", port = 2379 },
            { server = "10.0.1.11", port = 2379 },
            { server = "10.0.1.12", port = 2379 }
        }
        local ec = etcd_client.new(etcd_server_opt)

        -- add new service
        ec:add_http_service {
            http_req = "GET / HTTP/1.0\r\nHost: foo.com\r\n\r\n",
                        -- raw HTTP request for checking
            timeout = 1000,   -- 1 sec is the timeout for network operations
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
            valid_statuses = {200, 302},  -- a list valid HTTP status code
        }

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

        ec:add_custom_service("redis", {
            host = "127.0.0.1",
            port = 6379        
        })

        ec:spwan_heartbeat()
    }
}
```

Description
===========

This library performs etcd discovery client with healthcheck in NGINX.
