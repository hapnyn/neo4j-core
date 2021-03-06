require 'neo4j/core/cypher_session/adaptors'
require 'neo4j/core/cypher_session/responses/embedded'

module Neo4j
  module Core
    class CypherSession
      module Adaptors
        class Embedded < Base
          def initialize(path, options = {})
            fail 'JRuby is required for embedded mode' if RUBY_PLATFORM != 'java'
            fail ArgumentError, "Invalid path: #{path}" if !File.directory?(path)

            @path = path
            @options = options
          end

          def connect
            factory    = Java::OrgNeo4jGraphdbFactory::GraphDatabaseFactory.new
            db_service = factory.newEmbeddedDatabaseBuilder(@path)
            db_service.loadPropertiesFromFile(@options[:properties_file]) if @options[:properties_file]
            db_service.setConfig(@options[:properties_map])               if @options[:properties_map]

            @graph_db = db_service.newGraphDatabase
          end

          def query_set(queries)
            # I think that this is the best way to do a batch in embedded...
            # Should probably do within a transaction in case of errors...

            transaction do
              self.class.instrument_transaction do
                self.class.instrument_queries(queries)

                execution_results = queries.map do |query|
                  engine.execute(query.cypher, indifferent_params(query))
                end

                Responses::Embedded.new(execution_results).results
              end
            end
          end

          def start_transaction
            @transaction = @graph_db.begin_tx
          end

          def end_transaction
            if @transaction.nil?
              fail 'Cannot close transaction without starting one'
            end

            @transaction.success
            @transaction.close
          end

          def transaction_started?
            !!@transaction
          end

          def version
            if defined?(::Neo4j::Community)
              ::Neo4j::Community::NEO_VERSION
            elsif defined?(::Neo4j::Enterprise)
              ::Neo4j::Enterprise::NEO_VERSION
            else
              fail 'Could not determine embedded version!'
            end
          end

          instrument(:transaction, 'neo4j.core.embedded.transaction', []) do |_, start, finish, _id, _payload|
            ms = (finish - start) * 1000

            " #{ANSI::BLUE}EMBEDDED CYPHER TRANSACTION:#{ANSI::CLEAR} #{ANSI::YELLOW}#{ms.round}ms#{ANSI::CLEAR}"
          end

          private

          def indifferent_params(query)
            params = query.parameters
            params.each { |k, v| params[k] = HashWithIndifferentAccess.new(params[k]) if v.is_a?(Hash) && !v.respond_to?(:nested_under_indifferent_access) }
            HashWithIndifferentAccess.new(params)
          end

          def engine
            @engine ||= Java::OrgNeo4jCypherJavacompat::ExecutionEngine.new(@graph_db)
          end
        end
      end
    end
  end
end
