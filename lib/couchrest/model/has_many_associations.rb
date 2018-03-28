module CouchRest
  module Model
    module HasManyAssociations
      extend ActiveSupport::Concern

      module ClassMethods
        def find_by_attributes(*attributes)
          @find_by_attributes ||= attributes.map(&:to_s) || ['_id']
        end

        def find_or_initialize_by(attributes)
          params = attributes.deep_stringify_keys
          id = params['id'] || params['_id']
          (id.present? && find(id)) || find_by(params) || new(params)
        end

        def find_by(attributes)
          values = attributes.values_at(*find_by_attributes).map(&:to_s)
          return if values.any?(&:blank?)
          send(
            "find_by_#{find_by_attributes.join('_and_')}",
            values
          )
        end

        def has_many_associations
          @has_many_associations ||= []
        end

        def has_many(attrib, *options)
          opts = merge_has_many_association_options(attrib, options.first)

          property(opts[:collection_of], [String], opts)

          has_many_associations << attrib.to_sym

          create_has_many_setter(attrib, opts)
          create_has_many_getter(attrib, opts)
          create_has_many_after_save_callback(attrib, opts)
          create_dependent_destroy_before_destroy_callback(attrib, opts)
          create_dependent_nullify_before_destroy_callback(attrib, opts)
        end

        private

        def create_has_many_setter(attrib, options)
          class_eval <<-EOS, __FILE__, __LINE__ + 1
            def #{attrib}=(values)
              @#{attrib} = values.map do |value|
                attributes = value.merge('#{options[:foreign_key]}' => id)
                model = #{options[:proxy]}.find_or_initialize_by(attributes)
                model.#{options[:foreign_key]} = id
                model.attributes = attributes
                model
              end
            end
          EOS
        end

        def create_has_many_getter(attrib, options)
          class_eval <<-EOS, __FILE__, __LINE__ + 1
            def #{attrib}(reload = false)
              return @#{attrib} if @#{attrib}.present? && !reload
              @#{attrib} = #{options[:proxy]}.by_#{options[:foreign_key]}(key: id).to_a
            end
          EOS
        end

        def create_has_many_after_save_callback(attrib, options)
          return unless options[:autosave]

          after_save "save_associated_#{attrib}!".to_sym

          class_eval <<-EOS, __FILE__, __LINE__ + 1
            def save_associated_#{attrib}!
              #{attrib}.all? { |a| a.update_attributes(#{options[:foreign_key]}: id) } &&
                update_attributes(#{options[:collection_of]}: #{attrib}.map(&:id))
            end
          EOS
        end

        def create_dependent_destroy_before_destroy_callback(attrib, options)
          return if options[:dependent].to_s != 'destroy'

          before_destroy "destroy_associated_#{attrib}!".to_sym

          class_eval <<-EOS, __FILE__, __LINE__ + 1
            def destroy_associated_#{attrib}!
              #{attrib}.each(&:destroy)
            end
          EOS
        end

        def create_dependent_nullify_before_destroy_callback(attrib, options)
          return if options[:dependent].to_s != 'nullify'

          before_destroy "nullify_associated_#{attrib}!".to_sym

          class_eval <<-EOS, __FILE__, __LINE__ + 1
            def nullify_associated_#{attrib}!
              #{attrib}.all? { |a| a.update_attributes(#{options[:foreign_key]}: nil) }
            end
          EOS
        end

        def merge_has_many_association_options(attrib, options = {})
          opts = {
            foreign_key: attrib.to_s.singularize + '_id',
            class_name:  attrib.to_s.singularize.camelcase,
            allow_blank: false,
            dependent: nil,
            collection_of: attrib.to_s.singularize + '_ids',
            autosave: true
          }

          opts.merge!(options)

          opts[:proxy] ||= opts[:class_name]

          opts
        end
      end
    end
  end
end
