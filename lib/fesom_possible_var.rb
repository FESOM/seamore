require_relative "frequency.rb"


class FesomPossibleVar
  attr_reader :variable_id, :unit, :description, :time_method

  def initialize(variable_id, unit, description, time_method)
    @variable_id = variable_id
    @unit = unit
    @description = description
    @time_method = time_method
  end


  # Generates a collection of FesomPossibleVar objects based upon a FORTRAN code snippet
  #
  # Maps each line of the argument [String] code via a regex based upon the initialization of
  # this class, using attributes <variable_id>, <description>, and <unit>.
  #
  # Special handling of the variable "tso", which uses TimeMethods::POINT instead of the
  # default TimeMethods::Mean
  #
  # TODO(PG -- Reverse Engineering): I still need to find out of the regex **needs** the parameters
  # or if instead it is used to **figure out what values they should have for initialization**.
  #
  # NOTE(PG -- Reverse Engineering): This looks like the Ruby equivalent of a Python `classmethod`
  # and seems to implement an alternative way of constructing objects of this class.
  #
  # @param code [String] `FORTRAN` code to pare
  # @param sort [Boolean] Whether or not to return the variables sorted (alphabetically?) by `variable_id`.
  # @return [Array<FesomPossibleVar>] An array of FesomPossibleVar objects
  def self.create_from_fortran_code(code, sort: true)
    vars = code.split("\n").map do |init_line|
      /.+?, ['"](?<variable_id>[^,]+?)['"], ['"](?<description>.+?)['"], ['"](?<unit>[^,]+?)['"]\) *.*/ =~ init_line
      raise "could not parse all values: variable_id:#{variable_id.inspect}, unit:#{unit.inspect}, description:#{description.inspect}, code:'#{init_line}'" unless [variable_id, unit, description].all?
      if(variable_id == "tso")
        FesomPossibleVar.new variable_id, unit, description, TimeMethods::POINT
      else
        FesomPossibleVar.new variable_id, unit, description, TimeMethods::MEAN
      end
    end
    
    if(sort)
      vars.sort_by {|v| v.variable_id}
    else
      vars
    end
  end
  
  # Helper method to nicely print out this FesomPossibleVar.
  # @return [String]
  def to_s
    "#{@variable_id}: '#{@unit}' #{@time_method} '#{@description}'"
  end
end


# Fesom (revision 550 from 2018/06/07) gen_calcmeans.F90 with removed lines:
#   call passive_tracers_mean(i)%init(n3, 'ptr'//tracer_suffix, 'passive tracer '//tracer_suffix, '')
#   call age_tracers_mean(i)%init(n3, 'age'//tracer_suffix, 'age tracer '//tracer_suffix, 'Year')
FESOM_VARIABLE_INITIALIZATION_CODE = <<~'EOFHEREDOC'
  call volo_const%init(1, 'volo', 'total volume of liquid seawater', 'm3') ! this could be optimized, as the value does not change. we use the standard output writer procedure for simplicity
  call soga_mean%init(1, 'soga', 'global average sea water salinity', 'psu')
  call thetaoga_mean%init(1, 'thetaoga', 'global average sea water potential temperature ', 'degC')
  call siarean_mean%init(1, 'siarean', 'total area of sea ice in the Northern hemisphere', '1e6 km2')
  call siareas_mean%init(1, 'siareas', 'total area of sea ice in the Southern hemisphere', '1e6 km2')
  call siextentn_mean%init(1, 'siextentn', 'total area of all Northern-Hemisphere grid cells that are covered by at least 15 % areal fraction of sea ice', '1e6 km2')
  call siextents_mean%init(1, 'siextents', 'total area of all Southern-Hemisphere grid cells that are covered by at least 15 % areal fraction of sea ice', '1e6 km2')
  call sivoln_mean%init(1, 'sivoln', 'total volume of sea ice in the Northern hemisphere', '1e3 km3')
  call sivols_mean%init(1, 'sivols', 'total volume of sea ice in the Southern hemisphere', '1e3 km3')
  call zos_mean%init(n2, 'zos', 'dynamic sea level', 'm')
  call zossq_mean%init(n2, 'zossq', 'sea surface height squared. Surface ocean geoid defines z=0.', 'm2')
  call omldamax_mean%init(n2, 'omldamax', 'daily maximum ocean mixed layer thickness defined by mixing scheme', 'm')
  call pbo_mean%init(n2, 'pbo', 'pressure at ocean bottom', 'Pa') ! sea_water_pressure_at_sea_floor
  call tos_mean%init(n2, 'tos', 'sea surface temperature of liquid ocean', 'degC')
  call tso_mean%init(n2, 'tso', 'sea surface temperature of liquid ocean, sampled synoptically', 'K')
  call sos_mean%init(n2, 'sos', 'sea surface salinity ', 'psu')
  call evs_mean%init(n2, 'evs', 'computed as the total mass of water vapor evaporating from the ice-free portion of the ocean  divided by the area of the ocean portion of the grid cell', 'kg m-2 s-1')
  call sidmassevapsubl_mean%init(n2, 'sidmassevapsubl', 'The rate of change of sea-ice mass change through evaporation and sublimation divided by grid-cell area', 'kg m-2 s-1')
  call sifllatstop_mean%init(n2, 'sifllatstop', 'Dummy: Not computed in FESOM, rather in ECHAM. the net latent heat flux over sea ice', 'W m-2')
  call sistrxdtop_mean%init(n2, 'sistrxdtop', 'x-component of atmospheric stress on sea ice', 'N m-2')
  call sistrydtop_mean%init(n2, 'sistrydtop', 'y-component of atmospheric stress on sea ice', 'N m-2')
  call wfo_mean%init(n2, 'wfo', 'computed as the water  flux into the ocean divided by the area of the ocean portion of the grid cell.  This is the sum of the next two variables in this table', 'kg m-2 s-1')
  call uo_mean%init(n3, 'uo', 'Prognostic x-ward velocity component resolved by the model.', 'm s-1') ! u is ufmean(1:n3)
  call vo_mean%init(n3, 'vo', 'Prognostic x-ward velocity component resolved by the model.', 'm s-1') ! v is ufmean(1+n3:2*n3)
  call wo_mean%init(n3, 'wo', 'vertical component of ocean velocity', 'm s-1') 
  call thetao_mean%init(n3, 'thetao', 'sea water potential temperature', 'degC')
  call so_mean%init(n3, 'so', 'sea water salinity', 'psu')
  call opottemptend_mean%init(n3, 'opottemptend', 'tendency of sea water potential temperature expressed as heat content', 'W m-2')
  call sisnthick_mean%init(n2, 'sisnthick', 'actual thickness of snow (snow volume divided by snow-covered area)', 'm')
  call ice_area_fraction_mean%init(n2, 'sic', 'fraction of grid cell covered by sea ice.', '1.0')
  call sea_ice_thickness_mean%init(n2, 'sithick', 'actual (floe) thickness of sea ice (NOT volume divided by grid area as was done in CMIP5)', 'm')
  call sea_ice_volume_mean%init(n2, 'sivol', 'total volume of sea ice divided by grid-cell area (this used to be called ice thickness in CMIP5)', 'm')
  call sea_ice_x_velocity_mean%init(n2, 'siu', 'x-velocity of ice on native model grid', 'm s-1')
  call sea_ice_y_velocity_mean%init(n2, 'siv', 'y-velocity of ice on native model grid', 'm s-1')
  call sea_ice_speed_mean%init(n2, 'sispeed', 'speed of ice (i.e. mean absolute velocity) to account for back-and-forth movement of the ice', 'm s-1')
  call sea_ice_time_fraction_mean%init(n2, 'sitimefrac', 'fraction of time steps of the averaging period during which sea ice is present (sic > 0) in a grid cell', '1.0')
  call sisnmass_mean%init(n2, 'sisnmass', 'total mass of snow on sea ice divided by grid-cell area', 'kg m-2')
  call sistrxubot_mean%init(n2, 'sistrxubot', 'x-component of ocean stress on sea ice', 'N m-2')
  call sistryubot_mean%init(n2, 'sistryubot', 'y-component of ocean stress on sea ice', 'N m-2')
  call u2o_mean%init(n3, 'u2o', 'square of x-component of ocean velocity', 'm2 s-2')
  call v2o_mean%init(n3, 'v2o', 'square of y-component of ocean velocity', 'm2 s-2')
  call w2o_mean%init(n3, 'w2o', 'square of vertical component of ocean velocity', 'm2 s-2')
  call wso_mean%init(n3, 'wso', 'salinity times vertical component of ocean velocity', 'm s-1')
  call wto_mean%init(n3, 'wto', 'temperature times vertical component of ocean velocity', 'degC m s-1')
  call rho_mean%init(n3, 'rho', 'insitu density', 'kg/m3')
  call urho_mean%init(n3, 'urho', 'u * insitu density', 'm/s kg /m3')
  call vrho_mean%init(n3, 'vrho', 'v * insitu density', 'm/s kg /m3')
  call uv_mean%init(n3, 'uv', 'u*v', 'm2/s2')
  call uto_mean%init(n3, 'uto', 'temperature times x-component of ocean velocity', 'degC m s-1')
  call vto_mean%init(n3, 'vto', 'temperature times y-component of ocean velocity', 'degC m s-1')
  call uso_mean%init(n3, 'uso', 'salinity times x-component of ocean velocity', 'm s-1')
  call vso_mean%init(n3, 'vso', 'salinity times y-component of ocean velocity', 'm s-1')
  call mlotst_mean%init(n2, 'mlotst', 'mixed layer depth, computed with Levitus method (with 0.125 kg/m3 criterion)', 'm')
  call thdgr_mean%init(n2, 'thdgr', 'thermodynamic growth rate of eff. ice thickness', 'm/s')
  call thdgrsn_mean%init(n2, 'thdgrsn', 'melting rate of snow thickness', 'm/s')
  call uhice_mean%init(n2, 'uhice', 'zonal advective flux of eff. ice thickness', 'm.m/s')
  call vhice_mean%init(n2, 'vhice', 'meridional advective flux of eff. ice thickness', 'm.m/s')
  call uhsnow_mean%init(n2, 'uhsnow', 'zonal advective flux of eff. snow thickness', 'm.m/s')
  call vhsnow_mean%init(n2, 'vhsnow', 'meridional advective flux of eff. snow thickness', 'm.m/s')
  call flice_mean%init(n2, 'flice', 'rate of flooding snow to ice', 'm/s')
  call fsitherm_mean%init(n2, 'fsitherm', 'sea ice thermodynamic water flux into the ocean divided by the area of the ocean portion of the grid cell', 'kg m-2 s-1')
  call sisnconc_mean%init(n2, 'sisnconc', 'fraction of sea ice, by area, which is covered by snow, giving equal weight to every square metre of sea ice', '1')
  call sidmassth_mean%init(n2, 'sidmassth', 'Total change in sea-ice mass from thermodynamic processes divided by grid-cell area', 'kg m-2 s-1')
  call sidmasssi_mean%init(n2, 'sidmasssi', 'The rate of change of sea ice mass due to transformation of snow to sea ice divided by grid-cell area', 'kg m-2 s-1')
  call sidmasstranx_mean%init(n2, 'sidmasstranx', 'Includes transport of both sea ice and snow by advection', 'kg s-1 m-1')
  call sidmasstrany_mean%init(n2, 'sidmasstrany', 'Includes transport of both sea ice and snow by advection', 'kg s-1 m-1')
  call tair_mean%init(n2, 'tair', 'air temperature', 'degC')
  call shum_mean%init(n2, 'shum', 'air specific humidity', 'kg/kg')
  call lwrd_mean%init(n2, 'lwrd', 'atmosphere longwave radiation', 'W/m^2')
  call olat_mean%init(n2, 'olat', 'latent heat flux to ocean, downward positive', 'W/m^2')
  call olwout_mean%init(n2, 'olwout', 'longwave radiation from ocean, downward positve', 'W/m^2')
  call osen_mean%init(n2, 'osen', 'sensible heat flux to ocean, downward positive', 'W/m^2')
  call relax_salt_mean%init(n2, 'relax_salt', 'ocean surface salinity relaxation, >0 increase salinity', 'psu m/s')
  call uwind_mean%init(n2, 'uwind', 'Dummy: FESOM does not see it; zonal wind speed', 'm/s')
  call vwind_mean%init(n2, 'vwind', 'Dummy: FESOM does not see it ;meridional wind speed', 'm/s')
  call prlq_mean%init(n2, 'prlq', 'computed as the total mass of liquid water falling as liquid rain  into the ice-free portion of the ocean divided by the area of the ocean portion of the grid cell.', 'kg m-2 s-1')
  call prsn_mean%init(n2, 'prsn', 'at surface; includes precipitation of all forms of water in the solid phase', 'kg m-2 s-1')
  call runoff_mean%init(n2, 'runoff', 'runoff', 'm/s')
  call evap_mean%init(n2, 'evap', 'evaporation', 'm/s')
  call rsdo_mean%init(n2, 'rsdo', 'n/a', 'W/m^2')
  call hfds_mean%init(n2, 'hfds', 'This is the net flux of heat entering the liquid water column through its upper surface (excluding any "flux adjustment") .', 'W m-2')
  call wnet_mean%init(n2, 'wnet', 'net freshwater flux to ocean, downward positive', 'm/s')
  call virtual_salt_mean%init(n2, 'virtual_salt', 'virtual salt flux to ocean, >0 increase salinity', 'psu m/s')
  call tauuo_mean%init(n2, 'tauuo', 'This is the stress on the liquid ocean from overlying atmosphere, sea ice, ice shelf, etc.', 'N m-2')
  call tauvo_mean%init(n2, 'tauvo', 'This is the stress on the liquid ocean from overlying atmosphere, sea ice, ice shelf, etc.', 'N m-2')
  EOFHEREDOC
