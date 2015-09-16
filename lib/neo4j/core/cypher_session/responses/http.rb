require 'neo4j/core/cypher_session/responses'

module Neo4j
  module Core
    class CypherSession
      module Responses
        class HTTP < Base
          attr_reader :results, :request_data

          def initialize(faraday_response, request_data)
            @request_data = request_data

            validate_faraday_response!(faraday_response)

            @results = faraday_response.body[:results].map do |result_data|
              result_from_data(result_data[:columns], result_data[:data])
            end
          end

          def result_from_data(columns, entities_data)
            rows = entities_data.map do |entity_data|
              resolve_result_element entity_data[:row], entity_data[:rest]
            end

            Result.new(columns, rows)
          end

          def resolve_result_element(row_data, rest_data)
            row_data.each_with_index.map do |row_datum, i|
              rest_datum = rest_data[i]

              case
              when rest_datum[:labels]
                resolve_node(rest_datum)
              when rest_datum[:type]
                resolve_relationship(rest_datum)
              when rest_datum[:directions]
                resolve_path(row_datum, rest_datum)
              else
                fail "Was not able to determine result entity type: #{rest_data.inspect}"
              end
            end
          end

          private

          def resolve_node(rest_datum)
            ::Neo4j::Core::Node.new(rest_datum[:metadata][:id],
                                    rest_datum[:metadata][:labels],
                                    rest_datum[:data])
          end

          def resolve_relationship(rest_datum)
            ::Neo4j::Core::Relationship.new(rest_datum[:metadata][:id],
                                            rest_datum[:metadata][:type],
                                            rest_datum[:data])
          end

          def resolve_path(row_datum, rest_datum)
            nodes = rest_datum[:nodes].each_with_index.map do |url, i|
              Node.from_url(url, row_datum[2 * i])
            end
            relationships = rest_datum[:relationships].each_with_index.map do |url, i|
              Relationship.from_url(url, row_datum[(2 * i) + 1])
            end

            ::Neo4j::Core::Path.new(nodes, relationships, rest_datum[:directions])
          end

          def validate_faraday_response!(faraday_response)
            if error = faraday_response.body[:errors][0]
              fail CypherError, "#{ANSI::CYAN}#{error[:code]}#{ANSI::CLEAR}: #{error[:message]}"
            end

            return if (200..299).include?(status = faraday_response.status)

            fail CypherError, "Expected 200-series response for #{faraday_response.env.url} (got #{status})"
          end
        end
      end
    end
  end
end
