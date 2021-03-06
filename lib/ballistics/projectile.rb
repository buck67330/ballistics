require 'ballistics/yaml'

class Ballistics::Projectile
  YAML_DIR = 'projectiles'

  MANDATORY = {
    "name"   => :string,
    "cal"    => :float,
    "grains" => :count,
  }
  # one of these fields is mandatory
  BALLISTIC_COEFFICIENT = {
    "g1" => :float,
    "g7" => :float,
  }
  OPTIONAL = {
    "sd"       => :float,
    "intended" => :string,
    "base"     => :string,
    "desc"     => :string,
  }
  DRAG_FUNCTION = {
    "flat" => "g1",
    "boat" => "g7",
  }
  DRAG_NUMBER = {
    "g1" => 1,
    "g7" => 7,
  }

  # Load a built-in YAML file and instantiate projectile objects
  # Return a hash of projectile objects keyed by projectile id (per the YAML)
  #
  def self.find(file: nil, id: nil)
    Ballistics::YAML.find(klass: self, file: file, id: id)
  end

  # Normalize common flat-base and boat-tail terms to flat or boat
  #
  def self.base(candidate)
    c = candidate.to_s.downcase.gsub(/[\-\_ ]/, '')
    case c
    when "boat", "boattail", "bt"
      "boat"
    when "flat", "flatbase", "fb"
      "flat"
    else
      raise "unknown base: #{candidate}"
    end
  end

  # Convert e.g. G1 to 1
  #
  def self.drag_number(drag_function)
    DRAG_NUMBER.fetch(drag_function.to_s.downcase)
  end

  attr_reader(*MANDATORY.keys)
  attr_reader(*BALLISTIC_COEFFICIENT.keys)
  attr_reader(*OPTIONAL.keys)
  attr_reader :ballistic_coefficient, :yaml_data, :extra

  def initialize(hsh)
    @yaml_data = hsh
    MANDATORY.each { |field, type|
      val = hsh.fetch(field)
      Ballistics::YAML.check_type!(val, type)
      self.instance_variable_set("@#{field}", val)
    }

    # Extract ballistic coefficients per drag model (e.g. G1)
    # We need at least one
    #
    @ballistic_coefficient = {}
    BALLISTIC_COEFFICIENT.each { |field, type|
      if hsh.key?(field)
        val = hsh[field]
        if !Ballistics::YAML.check_type?(val, type)
          raise(TypeError, "#{val} (#{field}) is not #{type}")
        end
        self.instance_variable_set("@#{field}", val)
        @ballistic_coefficient[field] = val
      end
    }
    raise "no valid BC" if @ballistic_coefficient.empty?

    OPTIONAL.each { |field, type|
      if hsh.key?(field)
        val = hsh[field]
        val = val.to_s if field == "intended" and type == :string
        Ballistics::YAML.check_type!(val, type)
        if field == "base"
          @base = self.class.base(val)
        else
          self.instance_variable_set("@#{field}", val)
        end
      end
    }

    # Keep track of fields that we don't expect
    @extra = {}
    (hsh.keys -
     MANDATORY.keys -
     BALLISTIC_COEFFICIENT.keys -
     OPTIONAL.keys).each { |k|
      @extra[k] = hsh[k]
    }

    # Make sure @base and @drag_function are initialized so that
    # self.drag_function works without warnings
    #
    @base ||= nil
    @drag_function = nil
  end

  # Return the preferred drag function if there is a BC available
  #
  def drag_function
    return @drag_function if @drag_function
    @drag_function = @ballistic_coefficient.keys.first
    if @base
      preferred = DRAG_FUNCTION.fetch(@base)
      if @ballistic_coefficient.key?(preferred)
        @drag_function = preferred
      end
    end
    @drag_function
  end

  # Return the BC for the preferred drag function
  #
  def bc
    @ballistic_coefficient.fetch(self.drag_function)
  end

  # Return params that can be used by Ballistics::Problem
  #
  def params
    { drag_function: self.drag_function,
      drag_number: self.class.drag_number(self.drag_function),
      ballistic_coefficient: self.bc }
  end

  # Return lines of text separated by newlines
  #
  def multiline
    lines = ["PROJECTILE: #{@name}", "=========="]
    fields = {
      "Caliber" => @cal,
      "Grains" => @grains,
    }
    @ballistic_coefficient.each { |df, bc|
      fields["BC (#{df.upcase})"] = bc
    }
    fields["Desc"] = @desc if @desc
    fields.each { |name, val|
      lines << [name.rjust(7, ' '), val].join(': ')
    }
    lines.join("\n")
  end
end
