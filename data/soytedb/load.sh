#!/bin/sh

set -o errexit -o nounset

sqlite3 ${CMAP_ROOT}/db/soytedb.db < ${CMAP_ROOT}/sql/cmap.create.sqlite

cmap_admin.pl --action create_species \
              --species_full_name 'Glycine max' \
              --species_common_name Soybean \
              --species_acc Glycine_max \
              --datasource soytedb \
              --no-log

cmap_admin.pl --action create_map_set \
              --map_set_name 'Soybean TEs' \
              --map_set_acc soytedb \
              --map_type_acc genetic \
              --species_acc Glycine_max \
              --datasource soytedb \
              --no-log

cmap_admin.pl --action import_tab_data \
              --map_set_acc soytedb \
              --species_acc Glycine_max \
              --datasource soytedb \
              --no-log \
              ${CMAP_ROOT}/data/soytedb/Soybean-Soybean_TEs.dat
