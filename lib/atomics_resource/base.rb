require 'nokogiri'
require 'open-uri'
require 'net/http'

module AtomicsResource

  class Base

    ## class instance variables
    class << self
      attr_accessor :atomics_type, :table_name, :primary_key
      alias_method :set_atomics_type, :atomics_type=
      alias_method :set_table_name,   :table_name=
      alias_method :set_primary_key,  :primary_key=
    end

    ## Get method for array of columns (attr_accessor will break for arrays on inheritance).
    def self.columns
      @columns ||= []
    end

    ## Add a column.
    def self.column(value)
      columns << value
    end

    ## Quote value for Atomics in SQL statment; numeric arguments returned unquoted,
    ## strings in single quotes.
    def self.quote_value(value)
      value.match(/^\d+$/) ? value : "'#{value}'"
    end

    ## Build a SQL query string from hash of options passed to find.
    def self.construct_sql(options)
      sql = []
      sql << "SELECT "   + construct_sql_for_params(options[:select])
      sql << "FROM "     + construct_sql_for_params(options[:from])
      sql << "WHERE "    + construct_sql_for_conditions(options[:conditions]) if options[:conditions]
      sql << "ORDER BY " + construct_sql_for_params(options[:order]) if options[:order]
      sql << "LIMIT "    + options[:limit].to_s  if options[:limit]
      sql << "OFFSET "   + options[:offset].to_s if options[:offset]
      sql.join(' ')
    end

    ## Return string for SQL conditions from values params as string, array, or hash.
    def self.construct_sql_for_params(parms)
      case parms
      when Array; parms.map(&:to_s).join(',')
      when Hash;  parms.keys.map(&:to_s).join(',')
      else parms.to_s
      end
    end

    ## Return string for SQL conditions from options params as string, array, or hash.
    def self.construct_sql_for_conditions(option)
      case option
      when Array; construct_sql_for_array(option)
      when Hash;  construct_sql_for_hash (option) ## :TODO: implement this
      else option
      end
    end

    ## Construct string of conditions from an array of format plus values to substitute.
    ## Examples:
    ##   [ 'foo = ? AND bar = ?', 'hello', 99 ]
    ##   [ 'foo = %s AND bar = %d", 'hello', 99 ]
    def self.construct_sql_for_array(a)
      format, *values = a
      if format.include?("\?")
        raise ArgumentError unless format.count('\?') == values.size # sanity check right number args
        format.gsub(/\?/) { quote_value(values.shift.to_s) }         # replace all ? with args
      elsif format.blank?
        format
      else # replace sprintf escapes
        format % values.collect { |value| quote_value(value.to_s) }
      end
    end

    ## Construct string of conditions from a hash of format plus values to substitute.
    ## Allows conditions as hash of key/value pairs to be ANDed together.
    ## Examples:
    ##   { :foo => :hello, :bar => 99 }
    def self.construct_sql_for_hash(h)
      h.map{|k,v| "#{k}=#{quote_value(v.to_s)}"}.join(' AND ')
    end

    ## Calls find and returns array of all matches.
    def self.all(*args)
      find(:all, *args)
    end

    ## Calls find and returns first matching object.
    def self.first(*args)
      find(:first, *args)
    end

    ## Calls find and returns last matching object.
    def self.last(*args)
      find(:last, *args)
    end

    ## Find takes a list of conditions as a hash, and returns array of matching objects.
    ## If single argument is numeric, return first object to match by primary key.
    def self.find(*arguments)
      scope   = arguments.slice!(0)
      options = arguments.slice!(0) || {}

      case scope
      when :all   then find_every(options)          # Employee.find(:all,   :conditions => 'team_id = 156')
      when :first then find_every(options).first    # Employee.find(:first, :conditions => 'team_id = 156')
      when :last  then find_every(options).last     # Employee.find(:last,  :conditions => 'team_id = 156')
      else             find_single(scope, options)  # Employee.find(7923113)
      end
    end

    ## Return array of columns to use for SELECT statements, ensuring we get primary_key, or single
    ## string '*' if no columns set.
    def self.columns_or_default
      columns.empty? ? '*' : ([primary_key]+columns).uniq
    end

    ## Find array of all matching records.
    def self.find_every(options)
      defaults = { :select => columns_or_default, :from => table_name }
      sql = construct_sql(defaults.merge(options))
      find_by_sql(sql)
    end

    ## Find a single record with given primary key.
    def self.find_single(scope, options)
      defaults = { :select => columns_or_default, :from => table_name, :conditions => {primary_key => scope} }
      sql = construct_sql(defaults)
      find_by_sql(sql).first
    end

    ## Return string with whole URL for request, adding given SQL string as query.
    def self.construct_url_for_sql(sql)
      (host, port, path) = ATOMICS_CONFIG[atomics_type.to_s].values_at('host', 'port', 'path')
      "http://#{host}:#{port}#{path}&q=#{URI.escape(sql)}"      
    end

    ## Find matches using raw SQL statement given as a string.
    ## args:: string containing SQL statement.
    ## returns:: array of objects.
    def self.find_by_sql(sql)
      url = construct_url_for_sql(sql)

      ## get the xml doc as a nokogiri object
      doc = Nokogiri::XML(open(url))
      

      ## array of records
      records = doc.xpath('//record').to_a.map do |record|
        
        ## convert record into a hash with name => value
        hash = record.xpath('./field').inject({}) do |hash, field|
          hash[field.xpath('./name')[0].content] = field.xpath('./value')[0].content
          hash
        end

        ## instantiate record object
        new(hash)
      end

    end

    ## What uses this?
    def self.to_model
      self
    end

    ## instance variables
    attr_accessor :attributes

    ## Constructor allows hash as arg to set attributes.
    def initialize(attributes = {})
      hsh = {}
      @attributes = hsh.respond_to?(:with_indifferent_access) ? hsh.with_indifferent_access : hsh
      load(attributes)
    end

    ## Set attributes for an existing instance of this object.
    def load(attributes)
      raise ArgumentError, "expected an attributes Hash, got #{attributes.inspect}" unless attributes.is_a?(Hash)
      attributes.each do |key, value|
        @attributes[key.to_s] = value.dup rescue value
      end
      self
    end

    ## Return formatted inspection string for record with attributes listed.
    def inspect
      attributes_string = @attributes.map{|k,v| "#{k}: #{value_for_inspect(v)}"}.join(', ')
      "#<#{self.class} #{attributes_string}>"
    end

    ## Returns inspect for a value, with strings shortened to 50 chars, for use in Object.inspect.
    def value_for_inspect(value)
      if value.is_a?(String) && value.length > 50
        "#{value[0..50]}...".inspect
      else
        value.inspect
      end
    end

    ## Get attributes as methods, like active_model.
    def method_missing(method_symbol, *arguments)
      method_name = method_symbol.to_s
      if method_name =~ /=$/
        attributes[$`] = arguments.first
      elsif method_name =~ /\?$/
        attributes[$`]
      else
        return attributes[method_name] if attributes.include?(method_name)
        super
      end
    end

    ## Get attributes using hash syntax.
    def [](attr)
      attributes[attr]
    end

    ## Value of primary key.
    def id
      attributes[self.class.primary_key].to_i
    end

    ## What uses this?
    def to_key
      [id]
    end

    ## Return primary_key as param for object, for polymorphic route generation to work from object in view.
    def to_param
      attributes[self.class.primary_key]
    end

  end

  ## Do some mix-ins to get various bits of rails coolness, skip these for non-rails.
  if defined? RAILS_ROOT
    extend ActiveModel::Naming  # need this for model_name and variants, used to get paths from objects
  end

end
