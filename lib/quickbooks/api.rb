class Quickbooks::API
  include Quickbooks::Support

attr_reader :dtd_parser, :qbxml_parser, :schema_type

def initialize(schema_type = nil, opts = {})
  @schema_type = schema_type
  use_disk_cache, log_level = opts.values_at(:use_disk_cache, :log_level)

  unless valid_schema_type?
    raise(ArgumentError, "schema type required: #{valid_schema_types.inspect}") 
  end

  @dtd_file = get_dtd_file
  @dtd_parser = DtdParser.new(schema_type)
  @qbxml_parser = QbxmlParser.new(schema_type)

  load_qb_classes(use_disk_cache)

  # load the container class template into memory (significantly speeds up wrapping of partial data hashes)
  get_container_class.template(true)
end

def container
  get_container_class
end

def qbxml_classes
  cached_classes
end

# QBXML 2 RUBY

def qbxml_to_obj(qbxml)
  case qbxml
  when IO
    qbxml_parser.parse_file(qbxml)
  else
    qbxml_parser.parse(qbxml)
  end
end

def qbxml_to_hash(qbxml, include_container = false)
  qb_obj = qbxml_to_obj(qbxml)
  unless include_container
    qb_obj.inner_attributes
  else
    qb_obj.attributes
  end
end


# RUBY 2 QBXML

def hash_to_obj(data)
  key = data.keys.first
  value = data[key]

  key_path = find_nested_key(container.template(true), key)
  raise(RuntimeError, "#{key} class not found in api template") unless key_path

  wrapped_data = build_hash_wrapper(key_path, value)
  container.new(wrapped_data)
end

def hash_to_qbxml(data)
  hash_to_obj(data).to_qbxml.to_s
end


private 


def load_qb_classes(use_disk_cache = false)
  if use_disk_cache
    disk_cache = Dir["#{get_disk_cache_path}/*"]
    if disk_cache.empty?
      log.info "Warning: on disk schema cache is empty, rebuilding..."
      rebuild_schema_cache(false, true)
    else
      disk_cache.each {|file| require file }
    end
  else
    rebuild_schema_cache(false, false)
  end
end

# rebuilds schema cache in memory and writes to disk if desired
#
def rebuild_schema_cache(force = false, write_to_disk = false)
  dtd_parser.parse_file(@dtd_file) if (cached_classes.empty? || force)
  dump_cached_classes if write_to_disk
end

# writes dynamically generated api classes to disk
#
def dump_cached_classes
  cached_classes.each do |c|  
    File.open("#{get_disk_cache_path}/#{to_attribute_name(c)}.rb", 'w') do |f|
      f << Ruby2Ruby.translate(c)
    end
  end
end

# class methods

def self.log
  @@log ||= Logger.new(STDOUT, DEFAULT_LOG_LEVEL)
end


end
