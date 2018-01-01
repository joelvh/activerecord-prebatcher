require 'active_record/prebatcher/version'

module ActiveRecord
  class Prebatcher
    class MissingInverseOf < StandardError; end

    # @param [ActiveRecord::Relation] relation - Parent resources relation.
    def initialize(relation)
      @relation = relation
    end

    # @param [Array<String,Symbol>] association_names - Eager loaded association names. e.g. `[:users, :likes]`
    # @return [Array<ActiveRecord::Base>]
    def precount(*association_names)
      return [] unless records?

      association_names.each do |association_name|
        reflection = reflection_for(association_name)

        if reflection.inverse_of.nil?
          raise MissingInverseOf.new(
            "`#{reflection.klass}` does not have inverse of `#{@relation.klass}##{reflection.name}`. "\
            "Probably missing to call `#{reflection.klass}.belongs_to #{@relation.name.underscore.to_sym.inspect}`?"
          )
        end

        count_by_id = scope_for(association_name).count
        writer      = define_accessor(records.first, association_name)

        records.each do |record|
          record.public_send(writer, count_by_id.fetch(record.id, 0))
        end
      end
      records
    end

    def records
      @relation.to_a
    end

    def records?
      records.any?
    end

    private

    def scope_for(association_name)
      reflection = reflection_for(association_name)

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
    def define_accessor(record, association_name)
      reader_name = "#{association_name}_count"
      writer_name = "#{reader_name}="

      if !record.respond_to?(reader_name) && !record.respond_to?(writer_name)
        record.class.send(:attr_accessor, reader_name)
      end

      writer_name
    end
  end
end
