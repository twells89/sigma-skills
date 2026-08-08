# frozen_string_literal: true

module Sigma
  module FormulaAudit
    module_function

    SNAKE_REFERENCE = /\[([^\/\]]+)\/([A-Z0-9_]+)\]/.freeze

    def repair!(document)
      fixed_count = 0
      Array(document['elements']).each do |element|
        # Raw warehouse identifiers are valid and may intentionally remain
        # uppercase/snake case. The audit only repairs post-swap formulas.
        next if element.dig('source', 'kind') == 'warehouse-table'
        next unless element['columns'].is_a?(Array)

        alias_to_display = element['columns'].to_h { |column| [column['id'], column['name']] }
        element['columns'].each do |column|
          next unless column['formula']

          column['formula'] = column['formula'].gsub(SNAKE_REFERENCE) do
            prefix, snake = Regexp.last_match.captures
            display = alias_to_display[snake]
            if display && display != snake
              fixed_count += 1
              "[#{prefix}/#{display}]"
            else
              Regexp.last_match[0]
            end
          end
        end
      end
      fixed_count
    end
  end
end
