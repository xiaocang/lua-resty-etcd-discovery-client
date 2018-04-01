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
            ]=], -- etcd service info
            fall = 3,  -- # of successive failures before turning a peer down
            rise = 2,  -- # of successive successes before turning a peer up
        }
        local http_service_opt = {
            host = "127.0.0.1", -- http service server addr
            port = 8080,        -- http service server port
            http_params = {
                uri = "/monitor",
                headers = {
                    Host = "localhost",
                    ["User-Agent"] = "Etcd discovery client v0.1"
                }
            }, -- resty.http `request` method params
            timeout = 1000,   -- 1 sec is the timeout for network operations
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

Methods
=======

new
---
**syntax:**

**context:**

[Back to TOC](#table-of-contents)

Installation
============

If you are using [OpenResty](http://openresty.org) 1.9.3.2 or later, then you should already have this library (and all of its dependencies) installed by default (and this is also the recommended way of using this library). Otherwise continue reading:

You need to compile both the [ngx_lua](https://github.com/openresty/lua-nginx-module) and [ngx_lua_upstream](https://github.com/openresty/lua-upstream-nginx-module) modules into your Nginx.

The latest git master branch of [ngx_lua](https://github.com/openresty/lua-nginx-module) is required.

You need to configure
the [lua_package_path](https://github.com/openresty/lua-nginx-module#lua_package_path) directive to
add the path of your `lua-resty-upstream-healthcheck` source tree to [ngx_lua](https://github.com/openresty/lua-nginx-module)'s Lua module search path, as in

```nginx
# nginx.conf
http {
    lua_package_path "/path/to/lua-resty-upstream-healthcheck/lib/?.lua;;";
    ...
}
```

[Back to TOC](#table-of-contents)

TODO
====

- make it ready to run
- add `reg_custom_service` method to lib

[Back to TOC](#table-of-contents)

Bugs and Patches
================

Please report bugs or submit patches by

1. creating a ticket on the [GitHub Issue Tracker](https://github.com/xiaocang/lua-resty-etcd-discovery-client/issues),

[Back to TOC](#table-of-contents)

Author
======

Johnny Wang <johnnywang1991@msn.com>.

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2018, by xiaocang.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========
* the lua-resty-http module: https://github.com/pintsized/lua-resty-http
* the lua-resty-healthcheck module: https://github.com/openresty/lua-resty-upstream-healthcheck
* OpenResty: http://openresty.org

[Back to TOC](#table-of-contents)
