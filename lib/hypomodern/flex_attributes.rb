module Hypomodern # :nodoc:

  # Flex attributes allow for the common but questionable database design of
  # storing attributes in a thin key/value table related to some model.
  #
  # = Rationale for an update
  # 
  # This is an update to Eric Anderson's original flex_attributes plugin. It makes
  # few real changes, just bugfixes and tightening up the code here and there.
  # That said, there is one HUGE change here and that is this:
  # Your flex attributes are all treated as value-objects. This means that if
  # you want to write one, you'd best write everything that you want to persist.
  #
  # The reasoning for this has to do with Rails' SQL generation post 2.0. It was
  # blindly issuing SQL to "UPDATE *_attributes SET value = 'my_value'". That's it.
  # No qualification, no scoping. I tried disabling the partial updates feature,
  # but no dice. No sweat though, since I had actually kind of wanted this new
  # behavior all along.
  #
  # = Capabilities
  #
  # The FlexAttributes plugin is capable of modeling this problem in a intuitive
  # way. Instead of having to deal with a related model you treat all attributes
  # (both on the model and related) as if they are all on the model. The plugin
  # will try to save all attributes to the model (normal ActiveRecord behaviour)
  # but if there is no column for an attribute it will try to save it to a
  # related model whose purpose is to store these many sparsly populated
  # attributes.
  #
  # The main design goals are:
  #
  # * Have the flex attributes feel like normal attributes. Simple gets and sets
  #   will add and remove records from the related model.
  # * Allow a model to determine what a valid flex attribute is for a given
  #   related model so our model still can generate a NoMethodError.
  module FlexAttributes
    def self.included(base) # :nodoc:
        base.extend ClassMethods
    end

    module ClassMethods

      # Will make the current class have flex attributes.
      #
      #   class User < ActiveRecord::Base
      #     has_flex_attributes
      #   end
      #   eric = User.find_by_login 'eric'
      #   puts "My AOL instant message name is: #{eric.aim}"
      #   eric.phone = '555-123-4567'
      #   eric.save
      #
      # The above example should work even though "aim" and "phone" are not
      # attributes on the User model.
      #
      # The following options are available on for has_flex_attributes to modify
      # the behavior. Reasonable defaults are provided:
      #
      # class_name::
      #   The class for the related model. This defaults to the
      #   model name prepended to "Attribute". So for a "User" model the class
      #   name would be "UserAttribute". The class can actually exist (in that
      #   case the model file will be loaded through Rails dependency system) or
      #   if it does not exist a basic model will be dynamically defined for you.
      #   This allows you to implement custom methods on the related class by
      #   simply defining the class manually.
      # table_name::
      #   The table for the related model. This defaults to the
      #   attribute model's table name.
      # relationship_name::
      #   This is the name of the actual has_many
      #   relationship. Most of the type this relationship will only be used
      #   indirectly but it is there if the user wants more raw access. This
      #   defaults to the class name underscored then pluralized finally turned
      #   into a symbol.
      # foreign_key::
      #   The key in the attribute table to relate back to the
      #   model. This defaults to the model name underscored prepended to "_id"
      # name_field::
      #   The field which stores the name of the attribute in the related object
      # value_field::
      #   The field that stores the value in the related object
      # versioned::
      #   If the model you are storing these attributes on is versioned, then set
      #   this to ensure that your attributes will persist! Otherwise, they will
      #   all be torn down per save. N.B. the attributes are not versioned into
      #   a separate table, as they were with the old system. That's way too much
      #   overhead :).
      # version_column::
      #   Set this if the column you're using to store your version information
      #   isn't "version".
      # fields::
      #   A list of fields that are valid flex attributes. By default
      #   this is "nil" which means that all field are valid. Use this option if
      #   you want some fields to go to one flex attribute model while other
      #   fields will go to another. As an alternative you can override the
      #   #flex_attributes method which will return a list of all valid flex
      #   attributes. This is useful if you want to read the list of attributes
      #   from another source to keep your code DRY. The following
      #   provides an example:
      #
      #  class User < ActiveRecord::Base
      #    has_flex_attributes :class_name => 'Preferences'
      #
      #    def flex_attributes
      #      %w(project_search project_order user_search user_order)
      #    end
      #  end
      #
      #  eric = User.find_by_login 'eric'
      #  eric.project_order = 'name'     # Will save to Preferences
      #  eric.save # Carries out save so now values are in database
      #
      # If both a :fields option and #flex_attributes method is defined the
      # :fields option take precidence. This allows you to easily define the
      # field list inline for one model while implementing #flex_attributes
      # for another model and not having #flex_attributes need to determine
      # what model it is answering for. In both cases the list of flex
      # attributes can be a list of string or symbols
      #
      # The final and perhaps best alternative is the #is_flex_attribute?
      # method. This method is given the name of the attribute
      # in question. If you override this method then the #flex_attributes
      # method or the :fields option will have no affect. Use of this method
      # is ideal when you want to retrict the attributes but do so in a
      # algorithmic way.
      #
      # If you are using flex_attributes_filtered, it defines #is_flex_attribute?
      def has_flex_attributes(options={})
        # don't allow multiple calls
        return if self.included_modules.include?(Hypomodern::FlexAttributes::InstanceMethods)

        # Provide default options
        options[:class_name] ||= self.class_name + 'Attribute'
        options[:table_name] ||= options[:class_name].tableize
        options[:relationship_name] ||= options[:class_name].tableize.to_sym
        options[:foreign_key] ||= self.class_name.foreign_key
        options[:base_foreign_key] ||= self.name.underscore.foreign_key
        options[:name_field] ||= 'name'
        options[:value_field] ||= 'value'
        options[:versioned] ||= false
        options[:version_column] ||= "version"
        options[:fields].collect! {|f| f.to_s} unless options[:fields].nil?

        # set class-level reader
        class_inheritable_reader :flex_options
        # write options hash: N.B. we're now using a per-class instance store.
        write_inheritable_attribute :flex_options, options

        # Attempt to load related class. If not create it
        begin
          options[:class_name].constantize
        rescue
          Object.const_set(options[:class_name],
            Class.new(ActiveRecord::Base)).class_eval do
            def self.reloadable? #:nodoc:
              false
            end
          end
        end
        
        # Mix in instance methods
        send(:include, Hypomodern::FlexAttributes::InstanceMethods)

        # Modify attribute class
        attribute_class = options[:class_name].constantize
        base_class = self.name.underscore.to_sym
        attribute_class.class_eval do
          belongs_to base_class, :foreign_key => options[:base_foreign_key]
          set_primary_key options[:foreign_key] # ???
          alias_method :base, base_class # For generic access
          self.partial_updates = false # partial updates really hose these
        end

        # Modify main class
        class_eval do
          has_many options[:relationship_name],
            :class_name => options[:class_name],
            :table_name => options[:table_name],
            :foreign_key => options[:foreign_key],
            :dependent => :destroy

          # The following is only setup once
          # And yes, I know, it uses alias_method_chain. I know.
          unless private_method_defined? :method_missing_without_flex_attributes

            # Carry out delayed actions before save
            after_validation :save_flex_attributes

            # Make attributes seem real
            alias_method_chain :method_missing, :flex_attributes

            private

            alias_method_chain :read_attribute, :flex_attributes
            alias_method_chain :write_attribute, :flex_attributes
          end
        end
      end
    end

    module InstanceMethods

      # Will determine if the given attribute is a flex attribute.
      # Override this in your class to provide custom logic if
      # the #flex_attributes method or the :fields option are not flexible
      # enough. If you override this method :fields and #flex_attributes will
      # not apply at all unless you implement them yourself.
      def is_flex_attribute?(attr)
        attr = attr.to_s
        return flex_options[:fields].include?(attr) unless flex_options[:fields].nil?
        return flex_attributes.collect {|f| f.to_s}.include?(attr) unless flex_attributes.nil?
        true
      end

      # Return a list of valid flex attributes for the given model. Return
      # nil if any field is allowed. If you want to say no field is allowed
      # then return an empty array. If you just have a static list the :fields
      # option is most likely easier.
      def flex_attributes; nil end
      
      def purge_old_attributes
        flex_options[:purge] = true
      end
      
      ##
      # write_extended_attributes
      # takes an attribute hash, performs mass assignment. Useful!
      def write_extended_attributes(attrs)
        attrs.each do |k, val|
          self.send((k.to_s + "=").to_sym, val) if is_flex_attribute?(k)
        end
        self
      end

      private

      # Flex Attributes are treated as value objects, e.g. they are destroyed and rebuilt on save. FYI.
      def save_flex_attributes
        @save_flex_attr ||= []
        attribute_class = self.flex_options[:class_name].constantize
        base_foreign_key = self.flex_options[:base_foreign_key] # e.g. location_id
        value_field = self.flex_options[:value_field]
        name_field = self.flex_options[:name_field]
        foreign_key = self.flex_options[:foreign_key]
        
        # first, delete everything, unless we're not making changes:
        if self.flex_options[:purge] || !@save_flex_attr.empty?
          attribute_class.delete_all(deletion_query(foreign_key))
          related_attrs.reload
          self.flex_options.delete(:purge)
        end
        
        #now, rebuild things:
        @save_flex_attr.each do |pair|
          attr_name, value = pair
          parameters = {
            foreign_key => self.id,
            value_field => value,
            name_field => attr_name
          }
          parameters[self.flex_options[:version_column]] = self.send(flex_options[:version_column]) if self.flex_options[:versioned]
          
          build_related_attr_field( parameters )
        end
        @save_flex_attr = []
      end
      
      def deletion_query(foreign_key)
        query = "#{foreign_key} = #{self.id || 'NULL'}"
        if self.flex_options[:versioned]
          query += " AND #{self.flex_options[:version_column]} = #{self.send(flex_options[:version_column])}"
        end
        query
      end

      # Overrides ActiveRecord::Base#read_attribute
      def read_attribute_with_flex_attributes(attr_name)
        attr_name = attr_name.to_s unless attr_name.is_a?(String)
        if is_related?(attr_name)
          value_field = flex_options[:value_field]
          related_attr = related_flex_attr(attr_name)
          return nil if related_attr.nil?
          return related_attr.send(value_field)
        end
        read_attribute_without_flex_attributes(attr_name)
      end

      # Overrides ActiveRecord::Base#write_attribute
      def write_attribute_with_flex_attributes(attr_name, value)
        attr_name = attr_name.to_s unless attr_name.is_a?(String)
        if is_related?(attr_name)
          
          @save_flex_attr ||= []
          @save_flex_attr << [attr_name, value]
          
          return value
        end # /if
        write_attribute_without_flex_attributes(attr_name, value)
      end
      
      def build_related_attr_field(parameters)
        related_attrs.build( parameters )
      end

      # Implements flex-attributes as if real getter/setter methods
      # were defined.
      def method_missing_with_flex_attributes(method_id, *args, &block)
        begin
          method_missing_without_flex_attributes method_id, *args, &block
        rescue NoMethodError => e
          attr_name = method_id.to_s.sub(/\=$/, '')
          if is_related?(attr_name)
            if method_id.to_s =~ /\=$/
              return write_attribute_with_flex_attributes(attr_name, args[0])
            else
              return read_attribute_with_flex_attributes(attr_name)
            end
          end
          raise e
        end
      end

      # Retrieve the related flex attribute object
      def related_flex_attr(attr)
          name_field = flex_options[:name_field]
          if flex_options[:versioned]
            related_attrs.to_a.find {|r| r.send(name_field) == attr && r.send(flex_options[:version_column]) == self.send(flex_options[:version_column])}
          else
            related_attrs.to_a.find {|r| r.send(name_field) == attr}
          end
      end

      # Retrieve the collection of related flex attributes
      def related_attrs
        relationship = flex_options[:relationship_name]
        send relationship
      end

      # Yield only if attr_name is a flex_attribute
      def is_related?(attr_name)
        return false if self.class.column_names.include? attr_name
        is_flex_attribute?(attr_name)
      end

      # Returns the options for the flex attributes
      def flex_options
        self.class.flex_options
      end

    end
  end
end
