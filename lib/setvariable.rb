require 'fileutils'
require 'tempfile'

def setname(sourcedir, invar, outvar, year_begin = nil, year_end = nil, outdir = nil)

  def filter_files(sourcedir, invar = nil, year_begin = nil, year_end = nil)
    basenames = Dir.entries(sourcedir).select { |f| File.file?(File.join(sourcedir, f)) }.sort
    if invar
      basenames.select! { |f| f.include?(invar) }
    end

    start_index = nil
    end_index = nil

    if year_begin
      basenames.each_with_index do |f, index|
        if f.include?(year_begin.to_s)
          start_index = index
          break
        end
      end
    end

    if year_end
      basenames.each_with_index do |f, index|
        if f.include?(year_end.to_s)
          end_index = index + 1 # include the last entry
          break
        end
      end
    end

    basenames = basenames[start_index...end_index]
    basenames.map { |f| File.join(sourcedir, f) }
  end

  def prepare_outfiles(infiles, invar, outvar, outdir = nil)
    outfiles = infiles.map { |f| File.basename(f).gsub(invar, outvar) }
    if outdir
      outfiles.map! { |f| File.join(outdir, f) }
    end
    outfiles
  end



  def setname_cmds(infiles, outfiles, outvar)
    cmds = []
    infiles.zip(outfiles).each do |infile, outfile|
      unless File.exist?(outfile)
        cmd = "cdo setname,#{outvar} #{infile} #{outfile}"
        cmds << cmd
      end
    end
    cmds
  end

  outdir ||= Dir.mktmpdir
  infiles = filter_files(sourcedir, invar, year_begin, year_end)
  outfiles = prepare_outfiles(infiles, invar, outvar, outdir)
  cmds = setname_cmds(infiles, outfiles, outvar)
  
  cmds.each do |cmd|
    system(cmd)
  end

  outdir
end
