require_relative 'frequency.rb'


class FesomYearlyOutputFile # i.e. a netcdf file with one year of fesom output
  attr_reader :variable_id, :year, :path, :approx_interval, :frequency, :unit, :time_method

  def initialize(variable_id:, year:, month:, day:, path:, cdl_data: nil)
    raise "can not have both set: a path and CDL data" if (path && cdl_data)
    @variable_id = variable_id
    @year = year.to_i
    @path = path
    if path
      begin
        cdl = %x(ncdump -h #{path})
        @frequency = FesomYearlyOutputFile.frequency_from_cdl cdl
        @unit = FesomYearlyOutputFile.unit_from_cdl variable_id, cdl
      rescue RuntimeError => e
        raise "file #{path}: #{e.message}"
      end
    elsif cdl_data
      @frequency = FesomYearlyOutputFile.frequency_from_cdl cdl_data
      @unit = FesomYearlyOutputFile.unit_from_cdl variable_id, cdl_data
    end
    @approx_interval = Frequency.for_name(@frequency).approx_interval
    
    @time_method = Frequency.for_name(@frequency).time_method
  end
  
  
  def <=>(other)
    "#{@variable_id} #{@approx_interval} #{@frequency}" <=> "#{other.variable_id} #{other.approx_interval} #{other.frequency}"
  end
  
  
  def to_s
    "#{@variable_id} '#{unit}' [#{@frequency}]"
  end
  

  # variable unit from native fesom file CDL (i.e. ncdump)
  def self.unit_from_cdl(variable_id, cdl)
     match = /#{variable_id}:units = "(?<unit>.+)"/.match cdl # there seems to be an error with rubys "".=~ as we do not get access to the unis variable then interpolating variable_id, using //.match seems to solve this
     match[:unit]
  end


  # fetch frequency from native fesom file CDL (i.e. ncdump)
  # https://github.com/WCRP-CMIP/CMIP6_CVs/blob/master/CMIP6_frequency.json
  def self.frequency_from_cdl(cdl)
    match = /^.*?output_schedule.*/.match cdl
    sout = match.to_s

    /unit: (?<unit>\w) / =~ sout
    /rate: (?<rate>\d+)/ =~ sout
  
    case "#{unit}#{rate}"
    when "y1"
      "yr"
    when "m1"
      "mon"
    when "d1"
      "day"
    when /s\d+/
      # this frequency is based on fesom time steps, i.e. might be used to express 3-hourly
      puts "NOTE: assuming frequency rate of #{unit}#{rate} equals 3hr for netcdf CDL"
      # solution: read the time axis and see what delta t we really have

      # for tso the frequency should be 3hrPt now (i.e. instantaneous)      
      "3hrPt" # this is hackish but does apply for the PRIMAVERA runs (tso is the only 3-hourly variable)      
    else
      raise "unknown unit+rate <#{unit}#{rate}> for netcdf CDL"
    end    
  end

end