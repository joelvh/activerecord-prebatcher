require 'active_record/prebatcher/version'

module ActiveRecord
  class Prebatcher
    extend Forwardable

    class MissingInverseOf < StandardError; end

    CALCULATE_OPERATIONS = %i[average count maximum minimum sum].freeze

    # @param [ActiveRecord::Relation] relation - Parent resources relation.
    def initialize(relation)
      @relation = relation
      @batches  = {}
    end

    # `reader_name` - specify attribute name to store result in
    # `options` [Hash] - :finder, :key_column, :value_fetcher
    def pre_find(reader_name, options, &value_fetcher)
      options[:value_fetcher] = value_fetcher if block_given?

      (@batches[:find] ||= {}).merge!(reader_name.to_sym => options)
      
      self
    end

    # @param [Array<String,Symbol>] association_name and aggregated column - Eager loaded association names. e.g. `{purchases: :total}`
    # @return [Array<Prebatcher>]
    CALCULATE_OPERATIONS.each do |operation|
      define_method "pre_#{operation}" do |*options|
        pre_calculate(operation, *options)
      end
    end

    def pre_calculate(operation, *options)
      (@batches[operation.to_sym] ||= {}).merge!(options_for(*options))
      
      self
    end

    def find_each(options = {}, &block)
      @relation.find_in_batches(options) do |records|
        apply_binders(records, &block)
      end
    end

    def prebatch!(&block)
      apply_binders(@relation, &block)
    end

    alias_method :to_a, :prebatch!
    alias_method :to_ary, :to_a
    
    def_delegators :to_a, :[], :pretty_print

    def inspect
      "#<#{self.class}:0x#{self.__id__.to_s(16)} #{to_a.inspect}>"
    end

    private

    def apply_binders(records, &block)
      binders = build_binders_for(records)

      records.map do |record|
        binders.each do |binder|
          binder.call(record)
        end

        yield record

        record
      end
    end

    def build_binders_for(records)
      @batches.map do |operation, options|
        if CALCULATE_OPERATIONS.include?(operation)
          pre_calculate_binders_for(records, operation, options)
        elsif operation == :find
          pre_find_binders_for(records, options)
        end
      end.flatten
    end

    def pre_find_binders_for(records, association_names)
      association_names.map do |reader, options|
        finder, key_column, value_fetcher, one = options.values_at(:finder, :key_column, :value_fetcher, :one)
        writer = define_accessor(records.first, reader)

        values_by_record = records.each_with_object({}) do |record, hash|
          hash[record] = value_fetcher.call(record)
        end

        associated = finder.where(key_column => values_by_record.values.uniq).group_by{ |record| record[key_column] }

        -> (record) {
          results = associated[values_by_record[record]]
          record.public_send(writer, one ? results[0] : results )
        }
      end
    end

    def pre_calculate_binders_for(records, operation, association_names)
      association_names.map do |association_name, column_name|
        results_by_id = scope_for(association_name).public_send(operation, column_name)
        reader = [association_name, column_name, operation].compact.join('_')
        writer = define_accessor(records.first, reader)

        -> (record) { record.public_send(writer, results_by_id.fetch(record.id, 0)) }
      end
    end

    def options_for(*association_names)
      association_names.each_with_object({}) do |option, associations|
        if option.is_a?(Hash)
          associations.merge!(option.symbolize_keys)
        else
          associations[option.to_sym] = nil # :all
        end
      end
    end

    def scope_for(association_name)
      reflection = reflection_for(association_name)

      if reflection.inverse_of.nil?
        raise MissingInverseOf.new(
          "`#{reflection.klass}` does not have inverse of `#{@relation.klass}##{reflection.name}`. "\
          "Probably missing to call `#{reflection.klass}.belongs_to #{@relation.name.underscore.to_sym.inspect}`?"
        )
      end
      
      reflection.klass.where(reflection.inverse_of.name => @relation).group(
        reflection.inverse_of.foreign_key
      )
    end

    def reflection_for(association_name)
      @relation.klass.reflections.fetch(association_name.to_s)
    end

    # @param [ActiveRecord::Base] record
    # @param [String] association_name
    # @return [String] writer method name
    def define_accessor(record, reader_name)
      writer_name = "#{reader_name}="

      if !record.respond_to?(reader_name) && !record.respond_to?(writer_name)
        # TODO: Find alternative other than adding accessors dynamically at runtime
        record.class.send(:attr_accessor, reader_name)
      end

      writer_name
    end
  end
end
