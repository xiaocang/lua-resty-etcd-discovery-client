use strict;
use warnings;
use Cwd 'cwd';
use Test::Nginx::Socket;

our $pwd = cwd();

our $config = qq{
    location / {
        return 200;
    }
};

Test::Nginx::Socket::no_root_location();
run_tests();

__DATA__

=== TEST 1: init
--- http_config eval
qq{
    lua_package_path '$::pwd/lib/?.lua;;';

    init_worker_by_lua_block {
        local etcd_discovery_client
            = require "resty.etcd.discovery.client"

        local etcd_server_opt = {
            { server = "10.0.1.10", port = 2379 },
            { server = "10.0.1.11", port = 2379 },
            { server = "10.0.1.12", port = 2379 }
        }
        local ec = etcd_discovery_client.new(etcd_server_opt)
    }
}
--- config eval: $::config
--- request: GET /
--- error_code: 200
--- no_error_log: [error]
