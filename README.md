# seamore README file

seamore is a software to cmorize simulation data to a given CMIP6 data request. It is being used to create publication ready data from CMIP6 simulations using the Sea-ice Ocean Model (FESOM) of the Alfred Wegener Institute (AWI).
Any feedback is greatly appreciated, please mail to: Jan Hegewald <jan.hegewald@awi.de>

# Variables, Data Request and Tables
## Datarequests

[https://github.com/PCMDI/cmip6-cmor-tables](https://github.com/PCMDI/cmip6-cmor-tables)

[https://github.com/PRIMAVERA-H2020/cmip6-cmor-tables
PRIMAVERA_Data_Request_v1_0_3](https://github.com/PRIMAVERA-H2020/cmip6-cmor-tables
PRIMAVERA_Data_Request_v1_0_3)

## Controlled Vocabularies

[https://github.com/WCRP-CMIP/CMIP6_CVs](https://github.com/WCRP-CMIP/CMIP6_CVs)

## Global Attributes, CMIP6 File Naming, Directory Structure

[https://docs.google.com/document/d/1h0r8RZr_f3-8egBMMh7aqLwy3snpD6_MrDz1q8n5XUk/edit](https://docs.google.com/document/d/1h0r8RZr_f3-8egBMMh7aqLwy3snpD6_MrDz1q8n5XUk/edit)



# Basic Usage

From the command line type
`seamore help` to show basic instructions and a list of commands. Type `seamore help <COMMAND>` to get more detailed help for a specific command.

## Configuration File

Process a configuration file to create CMOR ready Fesom outout using the `process` command:

```
seamore process exampleconfig.seamore
``` 

The configuration file consists of 4 parts of ruby-DSL code for *seamore*.

### Part 1, the CMOR Data Request and other global information:

```
cmip6_cmor_tables "01.00.27", "/path/cmip6-cmor-tables/Tables"
cmip6_cvs_dir "/path/CMIP6_CVs"
merge_years_step 1
version_date 2018, 12, 18 # YYYY, MM, DD
source_id "AWI-CM-1-1-MR"
grid_description_file "/pool/glob/griddes.nc"
```

Note, the `merge_years_step` joins multiple years to a single file. Each new file will start at year xxx1, i.e. if files for the years 1950,1951,1952 are merged with `merge_years_step 2`, the resulting files will range from 1950--1950 and 1951--1952.


### Part 2, one or multiple blocks for each experiment id, i.e. *historical*, *piControl*, *abrupt-4xCO2*

```
experiment_id "piControl" do # name from controlled vocabularies, multiple expreiment_id blocks are allowed in a single file
  indir "/path/fesom_output", 2401, 2450 # optionally limit input to a range of years
  outdir "/path/seamore_generated"
  variant_label "r1i1p1f1" # see external Global Attributes document 
  parent_variant_label "r1i1p1f1" # must be omitted if there is "no parent" in the controlled vocabularies
  parent_first_year 1901 # must be omitted if there is "no parent" in the controlled vocabularies
  branch_year_in_parent 2401
end

```

### Part 3, steps of the processing pipeline

Remove or comment individual lines to skip a specific step.

```
cmorize_defaults do
  mergefiles
  time_seconds_to_days
  mean_timestamp_adjust
  auto_insert_time_bounds
  auto_downsample_frequency
  auto_convert_unit
  apply_grid
  set_global_attributes
  set_local_attributes
  fix_cf_names
  compress
  apply_cmor_filename
end

```

### Part 4, the variables to create during cmorization

The following lines can be generated from the `match_available` command, i.e.
```
seamore match_available /path/cmip6-cmor-tables/Tables /path/fesom_output
```

If variables can be found in the data request tables but have a different unit, `match_available` will list them as a comment and the mapping has to be entered manually. If *seamore* is able to automatically to the unit conversion, it can still generate the according cmorized file.

The format of the `cmorize` lines is:

```
<actual Fesom variable name>_<actual Fesom variable frequency> => [<cmore variable name>_<target table name>]
```
The frequencies and table names are part of the CMOR Tables and Controlled Vocabularies. If multiple output tables (frequencies) are requred for the same input variable, use a comma separated list for the output variables: `cmorize volo_mon => [volo_Omon, volo_Odec]`

Current automatic unit conversion includes:

psu to  0.001<br>
psu2 to  1e-06<br>
W/m^2 to  W m-2<br>
1.0 to  1<br>
1 to  %<br>
1.0 to  %<br>
K to  degC

Code fore these conversions belongs to the `AUTO_CONVERT_UNIT` class, currently in the `step.rb` file. [https://github.com/FESOM/seamore/blob/01e321231cf976b3459c61107853134dcc8412a7/lib/step.rb#L207](https://github.com/FESOM/seamore/blob/01e321231cf976b3459c61107853134dcc8412a7/lib/step.rb#L207)


```
cmorize evs_mon => [evs_Omon]
cmorize fsitherm_mon => [fsitherm_Omon]
cmorize hfds_mon => [hfds_Omon, hfds_Odec]
cmorize mlotst_day => [mlotst_Eday, mlotst_Omon]
cmorize omldamax_day => [omldamax_Oday]
cmorize opottemptend_mon => [opottemptend_Emon, opottemptend_Oyr]
cmorize pbo_mon => [pbo_Omon]
cmorize prsn_mon => [prsn_Omon]
cmorize rsdo_mon => [rsdo_Omon] # NO match: rsdo 'W/m^2' mon (!! rsdo 'W m-2' exists in datarequest)
cmorize siarean_mon => [siarean_SImon]
cmorize siareas_mon => [siareas_SImon]
cmorize sidmassevapsubl_mon => [sidmassevapsubl_SImon]
cmorize sidmasssi_mon => [sidmasssi_SImon]
cmorize sidmassth_mon => [sidmassth_SImon]
cmorize siextentn_mon => [siextentn_SImon]
cmorize siextents_mon => [siextents_SImon]
cmorize sifllatstop_mon => [sifllatstop_SImon]
cmorize sisnconc_mon => [sisnconc_SImon] # NO match: sisnconc '1' mon (!! sisnconc '%' exists in datarequest)
cmorize sisnmass_mon => [sisnmass_SImon]
cmorize sisnthick_mon => [sisnthick_SImon]
cmorize sispeed_mon => [sispeed_SImon]
cmorize sistrxdtop_day => [sistrxdtop_SImon]
cmorize sistrxubot_day => [sistrxubot_SImon]
cmorize sistrydtop_day => [sistrydtop_SImon]
cmorize sistryubot_day => [sistryubot_SImon]
cmorize sithick_day => [sithick_SIday, sithick_SImon]
cmorize sitimefrac_day => [sitimefrac_SIday, sitimefrac_SImon] # NO match: sitimefrac '1.0' day (!! sitimefrac '1' exists in datarequest)
cmorize siu_day => [siu_SIday, siu_SImon]
cmorize siv_day => [siv_SIday, siv_SImon]
cmorize sivol_mon => [sivol_SImon]
cmorize sivoln_mon => [sivoln_SImon]
cmorize sivols_mon => [sivols_SImon]
cmorize so_day => [so_Omon, so_Odec] # NO match: so 'psu' day (!! so '0.001' exists in datarequest)
cmorize soga_mon => [soga_Omon, soga_Odec] # NO match: soga 'psu' mon (!! soga '0.001' exists in datarequest)
cmorize sos_day => [sos_Oday, sos_Omon, sos_Odec] # NO match: sos 'psu' day (!! sos '0.001' exists in datarequest)
cmorize tauuo_day => [tauuo_Omon, tauuo_Odec]
cmorize tauvo_day => [tauvo_Omon, tauvo_Odec]
cmorize thetao_day => [thetao_Omon, thetao_Odec]
cmorize thetaoga_mon => [thetaoga_Omon, thetaoga_Odec]
cmorize tos_day => [tos_Oday, tos_Omon, tos_Odec]
cmorize tso_3hrPt => [tos_3hr] # NO match: tso 'K' 3hrPt
cmorize uo_mon => [uo_Omon, uo_Odec]
cmorize vo_mon => [vo_Omon, vo_Odec]
cmorize volo_mon => [volo_Omon, volo_Odec]
cmorize wfo_mon => [wfo_Omon, wfo_Odec]
cmorize wo_mon => [wo_Omon, wo_Odec]
cmorize zos_day => [zos_Omon]
cmorize zossq_mon => [zossq_Omon]

```

# Misc

Currently *seamore* utilizes the following commands to do the file conversion. See [https://github.com/FESOM/seamore/blob/01e321231cf976b3459c61107853134dcc8412a7/lib/file_command.rb#L5C11-L5C11](https://github.com/FESOM/seamore/blob/01e321231cf976b3459c61107853134dcc8412a7/lib/file_command.rb#L5C11-L5C11)

```
cdo
ncn
ncks
nccopy
ncatted
ncrename
```

## Aborted Jobs

If a `seamore process` job has been killed or `ctrl-c`ed, it can be resumed! Manually delete all `*.inprogress` from the output directoy and re-run the original `seamore process` command to resume cmorization.

## Tab Auto Completion

There is an autocompletion file for bash and zsh which can besourced to get autocomplete: [env/complete.sh](https://github.com/FESOM/seamore/blob/6d43a6fb894bd0502dc4ff153b39acb94ce0b6f8/env/complete.sh)


# Install Notes

## Automatic installation

If the environment scripts are already available for the machine you are using you'll
be able to run the following to automatically install seamore and build its
dependencies:

```
./configure.sh
```

Before starting using `bin/seamore` make sure you execute:

```
source env.sh
```

Machines that support this type of installation
- Albedo

## In case there is no ruby available

```
cd /path
wget https://cache.ruby-lang.org/pub/ruby/2.6/ruby-2.6.4.tar.gz
tar -xf ruby-2.6.4.tar.gz
mkdir ruby-2.6.4_bin
cd ruby-2.6.4
./configure --disable-install-doc --prefix=/path/ruby-2.6.4_bin
make -j `nproc --all`
make install
```

## Manual installation of seamore

```
cd /path/seamore && bundle install
# if bundle install fails, we only need gli
gem install --install-dir /path/rubygems/ gli
export GEM_PATH=$GEM_PATH:/path/rubygems/
```

One can add the seamore module file to .zshrc, .bashrc like `export MODULEPATH=/path/modules:$MODULEPATH`

Then to use seamore:

```
module load seamore

```

## Unit Tests

*seamore* contains a set of carefully written unit tests. To run:

```
cd src
ruby test/test.rb
```
