global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  redispatch
    retries 2
    timeout connect 3s
    timeout client  30s
    timeout server  30s

frontend http_in
    bind *:80
    default_backend apps

backend apps
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
    default-server inter 1s fall 2 rise 2
__SERVEURS__

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 2s