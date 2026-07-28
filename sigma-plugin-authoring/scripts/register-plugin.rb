#!/usr/bin/env ruby
# frozen_string_literal: true
#
# register-plugin.rb — idempotent Sigma custom-plugin registration helper.
#
# PluginRegister.register_or_get(name:, description:, url:) is IDEMPOTENT:
#   1. GET /v2/plugins first — if a plugin with this exact `name` already
#      exists, return its pluginId. Never creates a duplicate.
#   2. Else POST /v2/plugins {name,description,url,type:"element"}, then
#      re-GET /v2/plugins and find by name. A non-2xx POST is NEVER treated
#      as a hard failure by itself — Sigma is documented to sometimes return
#      a masked 404 (or other error) on an otherwise-successful register, so
#      the confirming GET is always attempted before deciding.
#   3. Only if, after POST+GET, the plugin still isn't found AND the POST
#      response clearly indicated an auth/permission failure (401/403) does
#      this raise PluginRegister::PermissionError: "plugin registration is
#      permission-gated (org-admin) — <detail>". Any other unresolved case
#      raises a plain error (never a faked pluginId).
#
# Full detail on both gotchas: reference/plugin-lifecycle.md §1.
#
# Usage (library):
#   $LOAD_PATH.unshift File.expand_path('lib', __dir__)
#   require 'sigma_rest'
#   require 'register-plugin'
#   plugin_id = PluginRegister.register_or_get(
#     name: "My Plugin", description: "...", url: "https://example.com/plugin/"
#   )
#
# Usage (CLI):
#   ruby scripts/register-plugin.rb "<name>" "<url>" ["<description>"]
#   -> prints the pluginId to stdout on success (exit 0); on failure, prints
#      an error to stderr and exits non-zero.
#
# Env: SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET (or an
#      SIGMA_API_TOKEN minted via the sigma-api skill). See
#      scripts/lib/sigma_rest.rb for the full auth/retry contract — it
#      auto-refreshes on a 401 mid-run.

require 'json'

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'

module PluginRegister
  # Raised only when a POST /v2/plugins failure is unambiguously an auth/
  # permission problem (401/403) AND the confirming GET also came up empty.
  class PermissionError < StandardError; end

  module_function

  # Look up a plugin by exact `name` via GET /v2/plugins. Returns the plugin
  # Hash (with at least a 'pluginId' or 'id' key) or nil if none matches.
  def find_by_name(name)
    list = Sigma.request(:get, '/v2/plugins?pageSize=1000')
    list = (JSON.parse(list) rescue nil) if list.is_a?(String)
    entries = (list.is_a?(Hash) && (list['entries'] || list['plugins'])) || []
    entries.find { |p| p['name'] == name }
  end

  # Idempotent register-or-get. Returns the pluginId (String). Raises
  # PermissionError on a confirmed 401/403 with no plugin found afterward, or
  # a plain RuntimeError for any other unresolved failure.
  def register_or_get(name:, description:, url:)
    existing = find_by_name(name)
    existing_id = existing && (existing['pluginId'] || existing['id'])
    return existing_id if existing_id

    post_error = nil
    begin
      Sigma.request(:post, '/v2/plugins',
                    body: JSON.generate(name: name, description: description, url: url, type: 'element'))
    rescue Sigma::Error => e
      # Never trust the POST's own status — the masked-404 quirk means even a
      # successful register can raise here. Always fall through to the
      # confirming GET below before deciding anything.
      post_error = e
    end

    plugin = find_by_name(name)
    plugin_id = plugin && (plugin['pluginId'] || plugin['id'])
    return plugin_id if plugin_id

    if post_error && post_error.message =~ /-> (401|403)\b/
      raise PermissionError,
            "plugin registration is permission-gated (org-admin) — #{post_error.message[0, 300]}"
    end

    raise "plugin registration failed: could not confirm pluginId for #{name.inspect} via " \
          "GET /v2/plugins after POST#{post_error ? " (POST raised: #{post_error.message[0, 300]})" : ' (POST returned 2xx)'}"
  end
end

if $PROGRAM_NAME == __FILE__
  name        = ARGV[0]
  url         = ARGV[1]
  description = ARGV[2] || ''

  if name.nil? || url.nil?
    warn 'Usage: ruby register-plugin.rb "<name>" "<url>" ["<description>"]'
    exit 2
  end

  begin
    plugin_id = PluginRegister.register_or_get(name: name, description: description, url: url)
    puts plugin_id
  rescue PluginRegister::PermissionError => e
    warn e.message
    exit 1
  rescue StandardError => e
    warn "register-plugin failed: #{e.message}"
    exit 1
  end
end
