# frozen_string_literal: true

require 'json'
require 'rexml/document'

module ReportSpec
  class Validator
    MAX_PAGES = 1_000
    MAX_PAGE_DIMENSION = 10_000

    DOCUMENTED_KINDS = %w[
      area-chart bar-chart combo-chart control divider geography-map image
      kpi-chart line-chart pivot-table point-map region-map scatter-chart
      table text
    ].freeze
    SCHEMA_ONLY_KINDS = %w[button embed input-table plugin].freeze
    UNSUPPORTED_KINDS = %w[progress waterfall-chart].freeze
    WORKBOOK_ONLY_KINDS = %w[
      chat container form navigation page-break repeated-container
      tabbed-container
    ].freeze
    FORBIDDEN_LAYOUT_ATTRIBUTES = %w[
      gridColumn gridRow gridTemplateColumns gridTemplateRows
    ].freeze

    attr_reader :errors, :warnings

    def initialize(payload, mode: :create)
      @payload = payload
      @mode = mode.to_sym
      @errors = []
      @warnings = []
    end

    def validate
      validate_envelope
      return self unless @document.is_a?(Hash)

      validate_document
      validate_pages
      validate_panels
      validate_elements
      validate_layout
      self
    end

    def valid?
      errors.empty?
    end

    private

    def validate_envelope
      unless @payload.is_a?(Hash)
        errors << 'root must be a JSON object'
        return
      end

      case @mode
      when :create
        %w[name folderId document].each do |key|
          errors << "missing required create field: #{key}" unless @payload.key?(key)
        end
      when :update
        errors << 'update body must contain exactly one property: document' unless @payload.keys == ['document']
      else
        errors << "unknown validation mode: #{@mode}"
      end

      @document = @payload['document']
      errors << 'document must be an object' unless @document.is_a?(Hash)
    end

    def validate_document
      %w[schemaVersion kind elements pages].each do |key|
        errors << "missing required document field: #{key}" unless @document.key?(key)
      end
      errors << 'document.schemaVersion must be a number' unless @document['schemaVersion'].is_a?(Numeric)
      errors << 'document.kind must be report' unless @document['kind'] == 'report'
      errors << 'document.elements must be an array' unless @document['elements'].is_a?(Array)
      errors << 'document.pages must be an array' unless @document['pages'].is_a?(Array)
      errors << 'document.panels must be an array when present' if @document.key?('panels') && !@document['panels'].is_a?(Array)
      warnings << 'document.settings is schema-published but not report-proven; preserve readback unchanged and verify carefully' if @document.key?('settings')

      config = @document['config']
      if config && !config.is_a?(Hash)
        errors << 'document.config must be an object when present'
        return
      end
      return unless config

      width = validate_number(config['pageWidth'], 'document.config.pageWidth', positive: true, max: MAX_PAGE_DIMENSION)
      height = validate_number(config['pageHeight'], 'document.config.pageHeight', positive: true, max: MAX_PAGE_DIMENSION)
      margin = validate_number(config['margin'], 'document.config.margin', nonnegative: true)
      errors << 'document.config.margin must leave positive page width' if width && margin && margin * 2 >= width
      errors << 'document.config.margin must leave positive page height' if height && margin && margin * 2 >= height
    end

    def validate_pages
      @pages = array(@document['pages'])
      errors << 'document.pages must contain at least one page' if @pages.empty?
      errors << "document.pages exceeds the #{MAX_PAGES}-page limit" if @pages.length > MAX_PAGES

      @page_ids = validate_ids(@pages, 'page')
      @pages.each_with_index do |page, index|
        unless page.is_a?(Hash)
          errors << "document.pages[#{index}] must be an object"
          next
        end
        errors << "page #{label(page, index)} must have a non-empty name" unless nonempty_string?(page['name'])
        errors << "page #{label(page, index)} must not contain nested elements" if page.key?('elements')
      end
    end

    def validate_panels
      @panels = array(@document['panels'])
      @panel_ids = validate_ids(@panels, 'panel')
      assignments = Hash.new { |hash, key| hash[key] = [] }

      @panels.each_with_index do |panel, index|
        unless panel.is_a?(Hash)
          errors << "document.panels[#{index}] must be an object"
          next
        end
        panel_label = label(panel, index)
        type = panel['type']
        errors << "panel #{panel_label} type must be header or footer" unless %w[header footer].include?(type)
        errors << "panel #{panel_label} must not contain nested elements" if panel.key?('elements')

        pages = panel['pages']
        if pages && !pages.is_a?(Array)
          errors << "panel #{panel_label} pages must be an array"
        else
          array(pages).each do |page_id|
            errors << "panel #{panel_label} references unknown page: #{page_id}" unless @page_ids.include?(page_id)
            assignments[[page_id, type]] << panel['id'] if %w[header footer].include?(type)
          end
        end

        config = panel['config']
        if config && !config.is_a?(Hash)
          errors << "panel #{panel_label} config must be an object"
        elsif config
          validate_number(config['height'], "panel #{panel_label} config.height", positive: true, max: MAX_PAGE_DIMENSION)
          if config.key?('backgroundColor') && !config['backgroundColor'].is_a?(String)
            errors << "panel #{panel_label} config.backgroundColor must be a string"
          end
        end
      end

      assignments.each do |(page_id, type), panel_ids|
        next unless panel_ids.length > 1

        errors << "page #{page_id} has more than one #{type} panel: #{panel_ids.join(', ')}"
      end
    end

    def validate_elements
      @elements = array(@document['elements'])
      @element_ids = validate_ids(@elements, 'element')

      @elements.each_with_index do |element, index|
        unless element.is_a?(Hash)
          errors << "document.elements[#{index}] must be an object"
          next
        end
        element_label = label(element, index)
        kind = element['kind']
        unless nonempty_string?(kind)
          errors << "element #{element_label} must have a non-empty kind"
          next
        end

        if UNSUPPORTED_KINDS.include?(kind)
          errors << "element #{element_label} kind #{kind} is unsupported for report authoring"
        elsif WORKBOOK_ONLY_KINDS.include?(kind)
          errors << "element #{element_label} kind #{kind} is workbook-only"
        elsif SCHEMA_ONLY_KINDS.include?(kind)
          warnings << "element #{element_label} kind #{kind} is schema-only; require live verify/readback/PDF evidence"
        elsif !DOCUMENTED_KINDS.include?(kind)
          warnings << "element #{element_label} kind #{kind} is unknown to this support matrix"
        end

        if kind == 'control' && element['controlType'] == 'synced'
          errors << "element #{element_label} uses unsupported synced controlType"
        end
      end
    end

    def validate_layout
      layout = @document['layout']
      if @elements.any? && !nonempty_string?(layout)
        errors << 'document.layout is required when document.elements is non-empty'
        return
      end
      return unless nonempty_string?(layout)

      if layout.match?(/<!DOCTYPE|<!ENTITY/i)
        errors << 'document.layout must not contain a DOCTYPE or ENTITY declaration'
        return
      end

      fragment = layout.sub(/\A\s*<\?xml[^?]*\?>\s*/m, '')
      xml = REXML::Document.new("<ReportLayout>#{fragment}</ReportLayout>")
      placements = Hash.new(0)
      page_roots = []
      panel_roots = []

      xml.root.elements.each do |root|
        case root.name
        when 'Page'
          page_roots << root.attributes['id']
          validate_region_root(root, 'Page', @page_ids, placements)
        when 'Panel'
          panel_roots << root.attributes['id']
          validate_region_root(root, 'Panel', @panel_ids, placements)
          validate_panel_root(root)
        else
          errors << "layout top-level node must be Page or Panel, got #{root.name}"
        end
      end

      validate_root_coverage(page_roots, @page_ids, 'page')
      validate_root_coverage(panel_roots, @panel_ids, 'panel')
      placements.each do |element_id, count|
        errors << "layout references undeclared elementId: #{element_id}" unless @element_ids.include?(element_id)
        errors << "element is placed more than once in layout: #{element_id}" if count > 1
      end
      (@element_ids - placements.keys).each { |id| errors << "element is not placed in layout: #{id}" }
    rescue REXML::ParseException => e
      errors << "document.layout is invalid XML: #{e.message.lines.first.strip}"
    end

    def validate_region_root(root, kind, declared_ids, placements)
      id = root.attributes['id']
      errors << "layout #{kind} is missing id" unless nonempty_string?(id)
      errors << "layout #{kind} references undeclared #{kind.downcase} id: #{id}" if nonempty_string?(id) && !declared_ids.include?(id)
      reject_grid_attributes(root, "layout #{kind} #{id || '(unnamed)'}")

      root.elements.each do |child|
        if child.name != 'Element'
          errors << "layout #{kind} #{id || '(unnamed)'} may contain only Element leaves, got #{child.name}"
          next
        end
        validate_layout_element(child, root, placements)
      end
    end

    def validate_layout_element(node, root, placements)
      element_id = node.attributes['elementId']
      unless nonempty_string?(element_id)
        errors << "layout Element under #{root.name} #{root.attributes['id']} is missing elementId"
        return
      end
      placements[element_id] += 1
      reject_grid_attributes(node, "layout Element #{element_id}")
      errors << "layout Element #{element_id} must not contain child nodes" if node.has_elements?

      x = validate_xml_number(node, 'x', element_id, nonnegative: true)
      y = validate_xml_number(node, 'y', element_id, nonnegative: true)
      width = validate_xml_number(node, 'width', element_id, positive: true)
      height = validate_xml_number(node, 'height', element_id, positive: true)
      return unless x && y && width && height

      page_width = number(@document.dig('config', 'pageWidth'))
      region_height = if root.name == 'Panel'
                        panel = @panels.find { |entry| entry.is_a?(Hash) && entry['id'] == root.attributes['id'] }
                        number(panel&.dig('config', 'height'))
                      else
                        number(@document.dig('config', 'pageHeight'))
                      end
      errors << "layout Element #{element_id} exceeds page width" if page_width && x + width > page_width
      errors << "layout Element #{element_id} exceeds #{root.name.downcase} height" if region_height && y + height > region_height
    end

    def validate_panel_root(root)
      panel = @panels.find { |entry| entry.is_a?(Hash) && entry['id'] == root.attributes['id'] }
      type = root.attributes['type']
      errors << "layout Panel #{root.attributes['id']} type must be header or footer" unless %w[header footer].include?(type)
      return unless panel && type

      errors << "layout Panel #{root.attributes['id']} type #{type} does not match metadata type #{panel['type']}" if panel['type'] != type
    end

    def validate_root_coverage(actual, declared, kind)
      actual.compact.group_by(&:itself).each do |id, copies|
        errors << "#{kind} is declared more than once in layout: #{id}" if copies.length > 1
      end
      (declared - actual.compact).each { |id| errors << "#{kind} is missing from layout: #{id}" }
    end

    def reject_grid_attributes(node, label)
      FORBIDDEN_LAYOUT_ATTRIBUTES.each do |attribute|
        errors << "#{label} uses forbidden workbook attribute #{attribute}" if node.attributes[attribute]
      end
    end

    def validate_xml_number(node, attribute, element_id, positive: false, nonnegative: false)
      raw = node.attributes[attribute]
      unless raw
        errors << "layout Element #{element_id} is missing #{attribute}"
        return
      end
      value = number(raw)
      unless value
        errors << "layout Element #{element_id} #{attribute} must be a finite number"
        return
      end
      errors << "layout Element #{element_id} #{attribute} must be positive" if positive && value <= 0
      errors << "layout Element #{element_id} #{attribute} must be non-negative" if nonnegative && value.negative?
      value
    end

    def validate_number(value, label, positive: false, nonnegative: false, max: nil)
      return unless value

      parsed = number(value)
      unless parsed
        errors << "#{label} must be a finite number"
        return
      end
      errors << "#{label} must be positive" if positive && parsed <= 0
      errors << "#{label} must be non-negative" if nonnegative && parsed.negative?
      errors << "#{label} must not exceed #{max}" if max && parsed > max
      parsed
    end

    def validate_ids(entries, kind)
      ids = []
      entries.each_with_index do |entry, index|
        next unless entry.is_a?(Hash)

        id = entry['id']
        if nonempty_string?(id)
          ids << id
        else
          errors << "#{kind} at index #{index} must have a non-empty id"
        end
      end
      ids.group_by(&:itself).each do |id, copies|
        errors << "duplicate #{kind} id: #{id}" if copies.length > 1
      end
      ids.uniq
    end

    def number(value)
      parsed = Float(value)
      parsed if parsed.finite?
    rescue ArgumentError, TypeError
      nil
    end

    def array(value)
      value.is_a?(Array) ? value : []
    end

    def nonempty_string?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def label(entry, index)
      entry['id'] || "at index #{index}"
    end
  end
end
