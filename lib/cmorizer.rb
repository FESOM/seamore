require_relative "step.rb"
require_relative "controlled_vocabularies.rb"
require_relative "fesom_output_dir.rb"
require_relative "global_attributes.rb"
require_relative "data_request.rb"
require_relative "steps_chain.rb"
require 'fileutils'


module CMORizer
  class Project
    def initialize(src_txt)
      @default_step_classes = []
      @cmorization_steps_chains = []
      @experiments = []
      @years_step = 1
      @eval_mode = true
      src_txt = sanitize src_txt
      instance_eval(src_txt, src_txt)
      @eval_mode = false
    end
    
    def sanitize(src_txt)
  # Sanitizes the source text to avoid mistreating variable names as Ruby constants
      new_txt = []
      requires_sanitization = false
      src_txt.each_line do |line|
        if line.start_with?("cmorize ") && line.include?("=>")
          first, varname, *rest = line.split
          if varname[0] =~ /[A-Z]/
            requires_sanitization = true
            new_txt << "#{varname} = '#{varname}'"
          end
        end
          new_txt << line
      end
      if requires_sanitization
        src_txt = new_txt.join("\n")
      end
      src_txt
      end
  
    def execute(threadcount)
      @experiments.each do |experiment|
        fesom_output_files = FesomOutputDir.new(experiment.indir, experiment.indir_first_year, experiment.indir_last_year).variable_files
        next if fesom_output_files.empty?
        
        # sort the fesom files
        fesom_output_files = fesom_output_files.sort_by {|ff| "#{ff.variable_id}#{ff.year}"}

        if(experiment.indir_first_year)
          execute_first_year = experiment.indir_first_year
        else
          # no explicit indir_first_year given in DSL, search for the lowest year in all files
          execute_first_year = (fesom_output_files.min {|a,b| a.year <=> b.year}).year
        end
        
        if(experiment.indir_last_year)
          execute_last_year = experiment.indir_last_year
        else
          # no explicit indir_last_year given in DSL, search for the highest year in all files
          execute_last_year = (fesom_output_files.max {|a,b| a.year <=> b.year}).year
        end
        experiment_year_ranges = Project.year_ranges_major_digits(first: execute_first_year.to_i, last: execute_last_year.to_i, step: @years_step, major_first_digit:1)
        
        FileUtils.mkdir_p experiment.outdir

        queue = Queue.new
        @cmorization_steps_chains.each do |chain|
          experiment_year_ranges.each do |year_range|
            queue << [chain, experiment, year_range, fesom_output_files]
          end
        end

        threads = []
        threadcount.times do
          threads << Thread.new(threads.size) do |threadname|
            Thread.current.name = "T#{threadname}"
        
            didanything = false
            while !queue.empty?
              args = queue.pop
              execute_year_range(*args)
              didanything = true
            end
            
            puts "#{Thread.current.name}: => #{Time.now} DONE <=" if didanything
          end
        end

        threads.each(&:join)
        threads.clear
      end
    end


    # executes cmorization for a year_range within a cmor-chain within an experiment, e.g. 10 years for a single variable of one experiment
    private def execute_year_range(chain, experiment, year_range, fesom_output_files)

      # fetch files for chain.fesom_variable_description + year_range
      filtered_fesom_files =
        fesom_output_files.select do |ff|
          if year_range.first <= ff.year && ff.year <= year_range.last
            if ff.variable_id == chain.input_variable_name && ff.frequency == chain.input_frequency_name
              true
            end
          end
        end
        
      # bail out if we do not have a continuous range of files
      required_number_of_files = year_range.last-year_range.first+1
      if filtered_fesom_files.size != required_number_of_files
        file_years = filtered_fesom_files.map {|ff| ff.year}
        raise "#{required_number_of_files-filtered_fesom_files.size} file(s) are missing for year range #{year_range} for input variable: '#{chain.input_variable_name}' from indir: '#{experiment.indir}', we got: #{filtered_fesom_files.map{|ff| ff.path}}"
      end

      unless filtered_fesom_files.empty?
        puts "#{Thread.current.name}: #{chain} #{year_range.first}-#{year_range.last}"
        begin
          chain.execute(filtered_fesom_files, experiment, @data_request, @grid_description_file, @version_date)
        rescue OutputFrequencyExceedsInputRangeError => e
          puts "#{Thread.current.name}: \033[1mskipping <#{chain} #{year_range.first}-#{year_range.last}> (#{e})\033[0m" # print in bold if possible using \033[1m \033[0m
        end
      end
    end

  
    def cmip6_cmor_tables(version, dir)
      @data_request = DataRequest.new_from_tables_dir(File.expand_path dir)
      raise "data request at #{dir} has version #{@data_request.version} but requested version is #{version}" unless version == @data_request.version
    end
  
  
    def cmip6_cvs_dir(d) # DSL setter
      d = File.expand_path d
      @controlled_vocabularies = ControlledVocabularies.new_from_dir d
    end
    
    
    def merge_years_step(s) # DSL setter
      @years_step = s
    end
    
    
    def version_date(y,m,d) # DSL setter
      @version_date = [y,m,d]
    end
    
    
    def source_id(id) # DSL setter
      @source_id = id
    end
  
  
    def grid_description_file(f) # DSL setter
      f = File.expand_path f
      raise "grid description file not readable: #{f}" unless File.readable?(f)
      @grid_description_file = f
    end


    def experiment_id(*args, &block)
      @experiments << Experiment.new(@source_id, args.shift, @data_request.version, @controlled_vocabularies, &block)
    end


    def cmorize_defaults(*args, &block)
      evaluater = Object.new
      def evaluater.method_missing(method_sym, *args, &block)
        # we assume every unknown method designates a default step
        sym = method_sym.upcase
        @default_steps ||= []
        @default_steps << sym
      end
      def evaluater.default_steps
        @default_steps ||= []
        @default_steps
      end
      evaluater.instance_eval(&block)
      @default_step_classes = evaluater.default_steps.map do |sym|
        c = CMORizer::Step.const_get(sym, false)
        raise "#{c} is not a class" unless c.is_a? Class
        c
      end
    end
  
  
    # "fesom name"_"available frequency" => ["variable_id"_"CMIP table_id"]
    def cmorize(*args, &block)
      hash = args.first
      in_description = hash.keys.first
      out_descriptions = hash.values.first
      out_descriptions.each do |out_desc|
        @cmorization_steps_chains << StepsChain.new(@default_step_classes, in_description, out_desc, &block)
      end
    end
    
    
    # generate year ranges, but prefer to start with the given major digit
    # i.e. if the major first digit is 1 and step is 10, we could get the ranges 50-50,51-60,61-70,71-72
    # if the major first digit is 0 and step is 10, we could get the ranges      50-59,60-69,70-72
    def self.year_ranges_major_digits(first:, last:, step:, major_first_digit:)
      raise "not a single digit: #{major_first_digit}" if major_first_digit.to_s.chars.size != 1
      
      first_digit = first.to_s.chars.last.to_i
      major_first = first + major_first_digit - first_digit
      major_first += 10 if major_first < first

      if(first <= major_first)
        ranges = year_ranges(first: first, last: major_first-1, step: step)
        ranges.concat year_ranges(first: major_first, last: last, step: step)
      end
      
      ranges
    end
    

    def self.year_ranges(first:, last:, step:)
      # this looks too complicated, but I am tired and it passes the tests
      ranges = []
      range_first = first
      range_last = first+step-1
      while range_last <= last do
        ranges << [range_first, range_last]
        range_first += step
        range_last += step
      end
      if(range_first <= last && range_last > last)
        ranges << [range_first, last]
      end
      ranges
    end


    private
    def method_missing(method_sym, *args, &block)
      return super unless @eval_mode
      method_sym.to_s
    end
  end


  class Experiment
    attr_reader :variant_label, :source_id, :nominal_resolution, :grid_txt, :data_request_version, :parent_experiment_info, :indir_first_year, :indir_last_year
    
    def initialize(source_id, experiment_id, data_request_version, controlled_vocabularies, &block)
      @source_id = source_id
      @experiment_id = experiment_id
      @data_request_version = data_request_version
      @experiment_cv = controlled_vocabularies['experiment_id'][@experiment_id]
      raise "experiment_id #{@experiment_id} does not exist in controlled vocabularies" unless @experiment_cv
      instance_eval(&block) if block_given?
      raise "source_id <#{source_id}> not found in controlled vocabularies" if controlled_vocabularies['source_id'][source_id].nil?
      @nominal_resolution = controlled_vocabularies['source_id'][source_id]['model_component']['ocean']['native_nominal_resolution']
      @grid_txt = controlled_vocabularies['source_id'][source_id]['model_component']['ocean']['description']
      
      parent_experiment_id = @experiment_cv['parent_experiment_id']
      parent_experiment_id = parent_experiment_id.join if parent_experiment_id.is_a? Array
      
      # parent_experiment_id might be set to "no parent", in which case our parent_experiment_cv would be nil
      parent_experiment_cv = controlled_vocabularies['experiment_id'][parent_experiment_id]
      parent_first_year_dsl = parent_first_year # make a copy here to not inadvertently mess with the state of the DSL setter
      if parent_experiment_cv.nil?
        if parent_variant_label || parent_first_year_dsl
          raise "we can not have parent_variant_label or parent_first_year set if parent_experiment_id is not present via controlled vocabularies experiment_id '#{@experiment_id}'"
        end
      else
        if parent_variant_label.nil?
          raise "we must have parent_variant_label set if parent_experiment_id is known ('#{parent_experiment_id}') via controlled vocabularies experiment_id '#{@experiment_id}'"
        end
        
        # see if we have a start year for the parent in the controlled vocabulary
        cv_parent_first_year = parent_experiment_cv['start_year']
        cv_parent_first_year = nil if cv_parent_first_year.empty?
        if cv_parent_first_year != nil
          @parent_first_year = cv_parent_first_year.to_i
          if parent_first_year_dsl != nil
            raise "we can not have a parent_first_year set if a start_year is known ('#{cv_parent_first_year}') via controlled vocabularies parent_experiment_id '#{parent_experiment_id}'"
          end
        elsif parent_first_year_dsl.nil?
          raise "we must have a parent_first_year set if a start_year is not known via controlled vocabularies parent_experiment_id '#{parent_experiment_id}'"
        end
      end
      
      @parent_experiment_info =
      if parent_experiment_cv
        parent_activity_id = parent_experiment_cv['activity_id']
        parent_activity_id = parent_activity_id.join if parent_activity_id.is_a? Array
        OpenStruct.new(:experiment_id => parent_experiment_id, :source_id => source_id, :activity_id => parent_activity_id, :variant_label => @parent_variant_label, :first_year => @parent_first_year, :branch_year => @branch_year_in_parent)
      else
        nil
      end      
    end
    
    
    def indir(d, first_year=nil, last_year=nil)
      @indir = File.expand_path d # DSL setter
      @indir_first_year = first_year
      @indir_last_year = last_year
      def self.indir # redefine to behave as getter
        @indir
      end
    end


    def outdir(d)
      @outdir = File.expand_path d # DSL setter
      def self.outdir # redefine to behave as getter
        @outdir
      end
    end

    
    def variant_label(l) # DSL setter
      @variant_label = l
      def self.variant_label # redefine to behave as getter
        @variant_label
      end
    end    
    
    
    def branch_year_in_parent(y=nil) # optional DSL setter (required if there is a parent)
      @branch_year_in_parent = y
      def self.branch_year_in_parent # redefine to behave as getter
        @branch_year_in_parent
      end
      @branch_year_in_parent
    end

    
    def parent_variant_label(l=nil) # optional DSL setter (required if there is a parent)
      @parent_variant_label = l
      def self.parent_variant_label # redefine to behave as getter
        @parent_variant_label
      end
      @parent_variant_label
    end

    
    def parent_first_year(y=nil) # optional DSL setter (required if there is a parent)
      @parent_first_year = y
      def self.parent_first_year # redefine to behave as getter
        @parent_first_year
      end
      @parent_first_year
    end


    def first_year
      if start_year.empty?
        nil # some experiment_id controlled vocabularies do not have a start_year, e.g. control-1950
      else
        start_year
      end
    end


    def last_year
      if end_year.empty?
        nil # some experiment_id controlled vocabularies do not have a end_year, e.g. control-1950
      else
        end_year
      end
    end


    def method_missing(method_sym, *args, &block)
      return super if (!args.empty? && !block_given?)
      # we assume we should get a key from our CV hash
      if @experiment_cv.has_key? method_sym.to_s
        if %w(parent_experiment_id activity_id sub_experiment_id).any? method_sym.to_s
          # the controlled vocabularies json files contain arrays here, but only a single item is allowed
          r = @experiment_cv[method_sym.to_s]
          r = r.join(' ') if r.is_a? Array
          return r
        end
        return @experiment_cv[method_sym.to_s]
      else
        super # not a hash key, so treat as a non-existing method
      end
    end
  end
end
