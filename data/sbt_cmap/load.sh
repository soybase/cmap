#!/bin/sh
set -o errexit -o nounset

DATASOURCE=sbt_cmap
SPECIES_ACC=Glycine_max # cmap_species.species_acc
SPECIES_NAME='Glycine max'  # display name
EVIDENCE_TYPE_ACC=ANB   # defined in cmap.conf
MAP_TYPE_ACC=genetic    # defined in cmap.conf

# create database
sqlite3 ${CMAP_ROOT}/db/${DATASOURCE}.db < ${CMAP_ROOT}/sql/cmap.create.sqlite

# create species
cmap_admin.pl --action create_species \
              --species_full_name "${SPECIES_NAME}" \
              --species_common_name Soybean \
              --species_acc ${SPECIES_ACC} \
              --datasource ${DATASOURCE} \
              --no-log

# create & load map sets
for map_set_file in ${CMAP_ROOT}/data/sbt_cmap/*.dat
do
    map_set_acc="$(basename $map_set_file .dat)" # strip "Soybean-
    # keep list of map set accessions for when generating correspondences
    map_set_accs="${map_set_accs:-}${map_set_accs:+ }$map_set_acc"
   

    # 2. create sequence map set
    cmap_admin.pl --action create_map_set \
                  --map_set_name ${map_set_acc} \
                  --map_set_acc ${map_set_acc} \
                  --map_type_acc ${MAP_TYPE_ACC} \
                  --species_acc ${SPECIES_ACC} \
                  --datasource ${DATASOURCE} \
                  --no-log

    cmap_admin.pl --action import_tab_data \
                  --map_set_acc ${map_set_acc}  \
                  --species_acc ${SPECIES_ACC} \
                  --datasource ${DATASOURCE} \
                  --no-log \
                  ${map_set_file}
done

# Create name-based correspondences between all map sets
cmap_admin.pl --action make_name_correspondences \
              --evidence_type_acc ANB \
              --from_map_set_accs "${map_set_accs}" \
              --allow_update \
              --datasource ${DATASOURCE} \
              --no-log

# The "ANALYZE" is very important for rendering correspondences -- I think it
# allows SQLite to intelligently choose which indexes to use in with the
# cmap_coorespondence_lookup table; otherwise it hangs when
# "cmap_correspondence_lookup.map_id1 = ..." is added to a query that CMap
# does to display correspondences.
sqlite3 ${CMAP_ROOT}/db/${DATASOURCE}.db 'ANALYZE'
