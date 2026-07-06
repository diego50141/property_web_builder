# frozen_string_literal: true

# Development-only: allow nip.io / sslip.io wildcard hosts through Rails'
# host authorization so the multi-tenant demo is reachable by subdomain
# without any DNS setup (e.g. http://default.187.77.211.121.nip.io:3100).
# These services resolve *.<ip>.nip.io to <ip>. Never used in production.
if Rails.env.development?
  Rails.application.config.hosts << /.*\.nip\.io/
  Rails.application.config.hosts << /.*\.sslip\.io/
end
