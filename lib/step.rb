# coding: iso-8859-1
require 'fileutils'

module CMORizer
  module Step
    class BaseStep
      attr_writer :forbid_inplace, :initial_prefix, :needs_to_run
      attr_reader :resultpath
    
      def initialize(next_step)
        @next_step = next_step
        @available_inputs = {}
        @forbid_inplace = false
        @initial_prefix = nil
        @needs_to_run = true
        @resultpath = nil
      end
      
      
      def set_info(outdir:, grid_description_file:, global_attributes:, fesom_variable_name:, fesom_variable_frequency:, fesom_unit:, out_unit:, variable_id:, description:, standard_name:, out_cell_methods:, out_cell_measures:)
        @outdir = outdir
        @grid_description_file = grid_description_file
        @global_attributes = global_attributes
        @fesom_variable_name = fesom_variable_name
        @fesom_variable_frequency = fesom_variable_frequency
        @fesom_unit = fesom_unit
        @out_unit = out_unit
        @variable_id = variable_id
        @description = description
        @standard_name = standard_name
        @out_cell_methods = out_cell_methods
        @out_cell_measures = out_cell_measures
      end


      def add_input(input, years, number_of_eventual_input_years, should_process)
        @available_inputs[years] = input
        
        # some steps might be able to process each file as soon as it arrives
        # others, like merge, might require the maximum number of files to be available
        if can_process?(number_of_eventual_input_years)
          sorted_years_arrays = @available_inputs.keys.sort
          sorted_inputs = @available_inputs.values_at(*sorted_years_arrays)

          sorted_years = sorted_years_arrays.flatten
          @resultpath = create_outpath(*sorted_inputs)
          process(sorted_inputs, sorted_years, @resultpath) if should_process
          results, result_years = [@resultpath], sorted_years
          
          if results && @next_step
            results.each_index do |i|
              @next_step.add_input(results[i], [result_years[i]], number_of_eventual_input_years, should_process)
            end
          end
          @available_inputs.clear
        end
      end
                  
      
      private def process(inputs, years, opath) # pipe input files through all our FileCommand objects
        prefix = "#{Thread.current.name}: " if Thread.current.name
        puts "#{prefix}\t#{self.class} #{inputs.join(', ')} #{opath}"
        *commands = file_commands
        if @forbid_inplace # bail out if this step is set to not manipulate a file inplace but all FileCommands of this step act inplace
          raise "#{self.class.to_s.split('::').last} is an inplace command" if commands.all? {|c| c.inplace?}
        end
        
        if @needs_to_run
          command_inputs = inputs
          command_opath = nil
          commands.each_with_index do |cmd, i|
            command_opath = "#{opath}.#{i}"
            cmd.run(command_inputs, command_opath)
            command_inputs = [command_opath]
          end
        
          if command_opath # i.e. commands array is empty
            FileUtils.mv command_opath, opath
          else
            raise "can not rename multiple inputs to a single output" if inputs.size > 1
            FileUtils.mv inputs[0], opath
          end          
        end
      end
            
      
      def file_commands
        raise "overwrite with concrete implementation for #{self.class} which returns one or many FileCommand objects"
      end
      
      
      # truncate to 10 characters so we do not get too long file names (apparently 255 chars max on mistral)
      # remove characters from the middle to make the result somewhat more readable
      def truncate_string(s)
        chars = s.chars
        loop do
          break if chars.size < 11
          chars.slice! 6
        end
        chars.join
      end
      
      
      def create_outpath(*inpaths)
        step_suffix = self.class.to_s.split('::').last
        step_suffix = truncate_string(step_suffix)        
        
        if @initial_prefix
          prefix = "#{@initial_prefix}"
        else
          prefix = File.basename(inpaths[0])
        end

        # keep filename less than 255 chars, as most systems can not deal with more
        outname = "#{prefix}.#{step_suffix}"
        
        File.join @outdir, outname
      end
    end
    
    
    class IndividualBaseStep < BaseStep
      def can_process?(number_of_eventual_input_years)
        true
      end
    end


    class JoinedBaseStep < BaseStep
      def can_process?(number_of_eventual_input_years)
        @available_inputs.keys.size == number_of_eventual_input_years
      end
    end
  end
end


class OutputFrequencyExceedsInputRangeError < StandardError
end


require_relative "file_command.rb"
module CMORizer
  module Step
    class MERGEFILES < JoinedBaseStep
      def file_commands
        CDO_MERGE_cmd.new        
      end
    end
    
    
    class AUTO_DOWNSAMPLE_FREQUENCY < BaseStep
      def can_process?(number_of_eventual_input_years)
        in_freq = Frequency.for_name(@fesom_variable_frequency)
        out_freq = Frequency.for_name(@global_attributes.frequency)
        
        if out_freq.name == "dec" && in_freq < out_freq
          raise OutputFrequencyExceedsInputRangeError.new "#{self.class} can not produce decadal output from #{number_of_eventual_input_years} input years (must have 10 years)" if number_of_eventual_input_years != 10
          return number_of_eventual_input_years == 10
        else
          return true
        end        
      end


      def file_commands
        cmds = []
        
        in_freq = Frequency.for_name(@fesom_variable_frequency)
        out_freq = Frequency.for_name(@global_attributes.frequency)

        if(in_freq != out_freq)
          case [in_freq.name, out_freq.name]
          when ["day", "mon"]
            # cdo monmean day_file mon_file
            cmds << CDO_MONMEAN_cmd.new
          when ["mon", "yr"]
            cmds << CDO_YEARMEAN_cmd.new
          when ["day", "dec"], ["mon", "dec"]
            cmds << CDO_TIMMEAN_cmd.new # this will just create a single mean output, so make sure we put in a 10 years file
          else
            raise "can not automatically downsample frequency from '#{in_freq.name}' to '#{out_freq.name}'"
          end
        end
        
        cmds
      end
    end
    
    
    class AUTO_CONVERT_UNIT < IndividualBaseStep
      def self.auto_convert_unit_possible?(from_unit, to_unit)
        begin
          AUTO_CONVERT_UNIT.convert_unit_commands(from_unit, to_unit)
        rescue RuntimeError => e
          return false
        end
        
        return true
      end
      
      
      def self.convert_unit_commands(from_unit, to_unit)
        cmds = []

        if(from_unit != to_unit)
          case [from_unit, to_unit]
          when ["psu", "0.001"] # noop
          when ["psu2", "1e-06"] # noop
          when ["W/m^2", "W m-2"] # noop
          when ["1.0", "1"] # noop
          when ["1", "%"]
            cmds << CDO_MULC_cmd.new(100)
          when ["1.0", "%"]
            cmds << CDO_MULC_cmd.new(100)
          when ["K", "degC"]
            cmds << CDO_SUBC_cmd.new(-273.15)
          when ["mmolC/m2/d", "kg m-2 s-1"]
            # notes on how this factor was derived (by chrisdane "Christopher Danek")
            # e.g. recom variable: CO2f => CMIP6_Omon.json: fgco2
            # 1) mmolC -> molC: /1e3
            # 2) molC -> gC: *12.0107
            # 3) gC -> kgC: /1e3
            # 4) d-1 -> s-1: /86400
            # -> mult_factor = 1/1e3*12.0107/1e3/86400 # = 1.390127e-10
            # In the CMIP6_Omon.json:fgco2 case, an additional sign change is necessary:
            # >0: into ocean -> >0: into atm: *-1
            # -> mult_factor = mult_factor*-1
            # COMMENT: For sign change use flip_sign function 
            cmds << CDO_MULC_cmd.new(1.390127e-10)
          when ["uatm", "Pa"]
            # notes on how this factor was derived (by chrisdane "Christopher Danek")
            # e.g. recom variable: pCO2s => CMIP6_Omon.json: spco2
            # 1) µatm -> atm: /1e6
            # 2) atm -> Pa: *1.01325e5 (1 atm = 1.01325e5 Pa)
            # -> mult_factor = 1/1e6*1.01325e5 # = 0.101325
            #
            # these notes are available on the following link
            # https://notes.desy.de/F8hTyk3PRielZrVdZRtyaQ?view#Seamore-missing-features-FESOM1-and-2
            cmds << CDO_MULC_cmd.new(0.101325)
          else
            raise "can not automatically convert unit from '#{from_unit}' to '#{to_unit}'"
          end          
        end
        
        cmds
      end
      
      
      def file_commands
        cmds = AUTO_CONVERT_UNIT.convert_unit_commands(@fesom_unit, @out_unit)
        unless cmds.empty?
          # apply unit
          # assume the APPLY_LOCAL_ATTRIBUTES Step will be executed later
          # and thus our variable has still the original name (@fesom_variable_name)
          cmds << NCATTED_SET_VARIABLE_UNITS_cmd.new(@fesom_variable_name, @out_unit)
        end
        
        cmds
      end
    end
    
    
    class CMOR_FILE < IndividualBaseStep
    end    
    

    class APPLY_CMOR_FILENAME < IndividualBaseStep
      def create_outpath(*inpaths)
        raise "can not create CMOR filename for multiple inputs" if inpaths.size > 1
        outname = @global_attributes.filename
                
        File.join @outdir, outname
      end
      
      def file_commands
        []
      end
    end
    
    
    class APPLY_GRID < IndividualBaseStep
      def file_commands
        cmds = []
        cmds << NCRENAME_DIMENSION_NODES_XD_TO_NCELLS_cmd.new
        cmds << NCKS_APPEND_GRID_cmd.new(@grid_description_file)
        # assume the APPLY_LOCAL_ATTRIBUTES Step will be executed later
        # and thus our variable has still the original name (@fesom_variable_name)
        cmds << NCATTED_APPEND_COORDINATES_VALUE_cmd.new(@fesom_variable_name)
        cmds
      end
    end
    
    
    class SET_LOCAL_ATTRIBUTES < IndividualBaseStep
      def file_commands
        cmds = []
        # rename our variable
        cmds << NCRENAME_RENAME_VARIABLE_cmd.new(@fesom_variable_name, @variable_id)

        # set standard_name from the data request cmip6-cmor-tables
        cmds << NCATTED_SET_VARIABLE_STANDARD_NAME_cmd.new(@variable_id, @standard_name)
        
        # apply description
        cmds << NCATTED_SET_VARIABLE_DESCRIPTION_cmd.new(@variable_id, @description)

        # apply cell_methods and cell_measures
        cmds << NCATTED_SET_VARIABLE_CELL_METHODS_CELL_MEASURES_cmd.new(@variable_id, @out_cell_methods, @out_cell_measures)
          
        cmds
      end
    end


    class SET_GLOBAL_ATTRIBUTES < IndividualBaseStep
      def file_commands
        cmds = []
        cmds << NCATTED_DELETE_GLOBAL_ATTRIBUTES_cmd.new(%w(output_schedule history CDO CDI Conventions))

        global_attributes_hash = @global_attributes.as_hash

        # apply global attributes
        cmds << NCATTED_ADD_GLOBAL_ATTRIBUTES_cmd.new(global_attributes_hash)
        cmds
      end
    end


    class FIX_CF_NAMES < IndividualBaseStep
      def file_commands
        cmds = []
        cmds << NCATTED_SET_LAT_LON_BNDS_STANDARD_NAME_cmd.new
        cmds << NCATTED_DELETE_VARIABLE_ATTRIBUTES_cmd.new("lat_bnds", %w(units standard_name centers))
        cmds << NCATTED_DELETE_VARIABLE_ATTRIBUTES_cmd.new("lon_bnds", %w(units standard_name centers))
        cmds
      end
    end
    
    
    class MEAN_TIMESTAMP_ADJUST < IndividualBaseStep
      def file_commands
        MEAN_TIMESTAMP_ADJUST_cmd.new
      end
    end
    
    
    class AUTO_INSERT_TIME_BOUNDS < IndividualBaseStep
      def file_commands
        in_freq = Frequency.for_name(@fesom_variable_frequency)
        cmds = []
        if in_freq.time_method == TimeMethods::MEAN
          cmds << INSERT_TIME_BOUNDS_cmd.new
        end      
        cmds
      end
    end
    
    
    class Unit_K_to_degC < IndividualBaseStep
    end
    

    class TIME_SECONDS_TO_DAYS < IndividualBaseStep
      def file_commands
        CDO_SET_T_UNITS_DAYS_cmd.new
      end
    end


    class COMPRESS < IndividualBaseStep
      def file_commands
        NCCOPY_COMPRESS_cmd.new
      end
    end

  end
end
