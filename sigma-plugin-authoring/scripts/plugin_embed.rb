# frozen_string_literal: true
# plugin_embed.rb — emits the VERIFIED Sigma {kind:"plugin"} element block.
# ALL config values are bare strings (object form is rejected, masked
# "Invalid kind:\"plugin\""). Stdlib only (json); Ruby 2.6-compatible.
require 'json'
module PluginEmbed
  def self.build(id:, plugin_id:, source_element_id:, bindings:, extra_config: {})
    raise ArgumentError, 'id required' if id.to_s.empty?
    raise ArgumentError, 'plugin_id required' if plugin_id.to_s.empty?
    raise ArgumentError, 'source_element_id required' if source_element_id.to_s.empty?
    config = { 'source' => { 'kind' => 'element', 'elementId' => source_element_id } }
    (bindings || {}).each { |k, v| config[k.to_s] = v.to_s }        # bare string columnId
    (extra_config || {}).each { |k, v| config[k.to_s] = v.to_s }    # ALL config values -> string
    { 'id' => id, 'kind' => 'plugin', 'pluginId' => plugin_id, 'config' => config }
  end
end
