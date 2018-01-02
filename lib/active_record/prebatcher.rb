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

    # @param [Array<String,Symbol>] association_name and aggregated column - Eager loaded association names. e.g. `{purchases: :total}`
    # @return [Array<Prebatcher>]
    CALCULATE_OPERATIONS.each do |operation|
      define_method "pre_#{operation}" do |*options|
        pre_calculate(operation, *options)
      end

      define_method "pre_#{operation}!" do |*options|
        pre_calculate!(operation, *options)
      end
    end

    def pre_calculate(operation, *options)
      (@batches[operation.to_sym] ||= {}).merge!(options_for(*options))
      
      self
    end

    def pre_calculate!(operation, *options)
      return [] unless records?

      associations = options_for(*options)

      associations.each do |association_name, column_name|
        results_by_id = scope_for(association_name).public_send(operation, column_name)
        reader = [association_name, column_name, operation].compact.join('_')
        writer = define_accessor(records.first, reader)

        records.each do |record|
          record.public_send(writer, results_by_id.fetch(record.id, 0))
        end
      end

      records
    end

    def prebatch!
      unless prebatched?
        @batches.each do |operation, options|
          public_send(:"pre_#{operation}!", options)
        end

        @prebatched = true
      end

      records
    end

    alias_method :to_a, :prebatch!
    alias_method :to_ary, :to_a
    
    def_delegators :to_a, :[], :pretty_print

    def prebatched?
      @relation.loaded? && @prebatched == true
    end

    def records
      @relation.to_a
    end

    def records?
      records.any?
    end

    def inspect
      "#<#{self.class}:0x#{self.__id__.to_s(16)} #{to_a.inspect}>"
    end

    private

    def options_for(*options)
      options.each_with_object({}) do |option, associations|
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
