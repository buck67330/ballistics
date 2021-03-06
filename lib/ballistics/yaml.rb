require 'yaml'

# We don't depend on the Ballistics module, so it may not have been loaded yet
module Ballistics; end

module Ballistics::YAML
  class UnknownType < RuntimeError; end
  class TypeMismatch < RuntimeError; end
  class LoadError < RuntimeError; end
  class MandatoryFieldError; end

  # Return a hash keyed by subdir with array values
  # Array contains short names for the subdir's yaml files
  # e.g. { 'cartridges' => ['300_blk'] }
  #
  BUILT_IN = {}
  Dir[File.join(__dir__, '*')].each { |fn|
    if File.directory? fn
      yaml_files = Dir[File.join(fn, '*.yaml')]
      if !yaml_files.empty?
        BUILT_IN[File.basename fn] =
          yaml_files.map { |y| File.basename(y, '.yaml') }
      end
    end
  }

  def self.load_built_in(dir, short_name)
    files = BUILT_IN[dir] or raise(LoadError, "unknown dir: #{dir}")
    filename = [short_name, 'yaml'].join('.')
    if files.include?(short_name)
      ::YAML.load_file(File.join(__dir__, dir, filename))
    else
      raise(LoadError, "unknown short name: #{short_name}")
    end
  end

  def self.find(klass:, file: nil, id: nil)
    candidates = {}
    objects = {}
    yd = klass::YAML_DIR or raise("no YAML_DIR for #{klass}")
    if file
      candidates = self.load_built_in(yd, file)
    else
      BUILT_IN.fetch(yd).each { |f|
        candidates.merge!(self.load_built_in(yd, f))
      }
    end
    if id
      klass.new candidates.fetch id
    else
      candidates.each { |cid, hsh|
        obj = klass.new hsh
        if block_given?
          objects[cid] = obj if yield obj
        else
          objects[cid] = obj
        end
      }
      objects
    end
  end

  def self.check_type?(val, type)
    case type
    when :string, :reference
      val.is_a?(String)
    when :float
      val.is_a?(Numeric)
    when :percent
      val.is_a?(Numeric) and val >= 0 and val <= 1
    when :count
      val.is_a?(1.class) and val >= 0
    when :int
      val.is_a?(1.class)
    else
      raise UnknownType, type
    end
  end

  def self.check_type!(val, type)
    self.check_type?(val, type) or raise(TypeMismatch, [val, type].join(' '))
  end
end
