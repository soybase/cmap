#!/bin/sh
set -o errexit -o nounset

DATASOURCE=sequence_genetic4
SPECIES_ACC=Glycine_max    # cmap_species.species_acc
SPECIES_NAME='Glycine max' # display name
EVIDENCE_TYPE_ACC=ANB      # evidence type (defined in cmap.conf)

# genetic map
GENETIC_MAP_CMAP_INPUT_FILE=${CMAP_ROOT}/data/sequence_genetic4/Cons4.0_110608.CMap_cM
GENETIC_MAP_SET_ACC=GmConsensus40cM
GENETIC_MAP_SET_NAME='Consensus 4.0 genetic order' # display name
GENETIC_MAP_TYPE_ACC=genetic # defined in cmap.conf

# sequence map
SEQUENCE_MAP_CMAP_INPUT_FILE=${CMAP_ROOT}/data/sequence_genetic4/Cons4.0_110608.CMap_bp
SEQUENCE_MAP_SET_NAME='Consensus 4.0 sequence order' # display name
SEQUENCE_MAP_SET_ACC=GmConsensus40bp
SEQUENCE_MAP_TYPE_ACC=sequence   # defined in cmap.conf

# 1. create database

sqlite3 ${CMAP_ROOT}/db/${DATASOURCE}.db < ${CMAP_ROOT}/sql/cmap.create.sqlite

cmap_admin.pl --action create_species \
              --species_full_name "${SPECIES_NAME}" \
              --species_common_name Soybean \
              --species_acc ${SPECIES_ACC} \
              --datasource ${DATASOURCE} \
              --no-log

# 2. create sequence map set
cmap_admin.pl --action create_map_set \
              --map_set_name "${SEQUENCE_MAP_SET_NAME}" \
              --map_set_acc ${SEQUENCE_MAP_SET_ACC} \
              --map_type_acc ${SEQUENCE_MAP_TYPE_ACC} \
              --species_acc ${SPECIES_ACC} \
              --datasource ${DATASOURCE} \
              --no-log

# 3. create genetic map set
cmap_admin.pl --action create_map_set \
              --map_set_name "${GENETIC_MAP_SET_NAME}" \
              --map_set_acc ${GENETIC_MAP_SET_ACC} \
              --map_type_acc ${GENETIC_MAP_TYPE_ACC} \
              --species_acc ${SPECIES_ACC} \
              --datasource ${DATASOURCE} \
              --no-log

# 4. load genetic map set
cmap_admin.pl --action import_tab_data \
                    --map_set_acc ${GENETIC_MAP_SET_ACC}  \
                    --species_acc ${SPECIES_ACC} \
                    --datasource ${DATASOURCE} \
                    --no-log \
                    ${GENETIC_MAP_CMAP_INPUT_FILE}

# 4. load sequence map set
cmap_admin.pl --action import_tab_data \
                    --map_set_acc ${SEQUENCE_MAP_SET_ACC} \
                    --species_acc ${SPECIES_ACC} \
                    --datasource ${DATASOURCE} \
                    --no-log \
                    ${SEQUENCE_MAP_CMAP_INPUT_FILE}
#
# 5. create correspondences
# the evidence_type_acc is defined in cmap.conf.

cmap_admin.pl --action make_name_correspondences \
              --evidence_type_acc ${EVIDENCE_TYPE_ACC} \
              --from_map_set_accs ${SEQUENCE_MAP_SET_ACC} \
              --to_map_set_accs ${GENETIC_MAP_SET_ACC} \
              --allow_update \
              --datasource ${DATASOURCE} \
              --no-log

cmap_admin.pl --action make_name_correspondences \
              --evidence_type_acc ${EVIDENCE_TYPE_ACC} \
              --from_map_set_accs ${GENETIC_MAP_SET_ACC}\
              --to_map_set_accs ${SEQUENCE_MAP_SET_ACC} \
              --allow_update \
              --datasource ${DATASOURCE} \
              --no-log

# The "ANALYZE" is very important for rendering correspondences -- I think it
# allows SQLite to intelligently choose which indexes to use in with the
# cmap_coorespondence_lookup table; otherwise it hangs when
# "cmap_correspondence_lookup.map_id1 = ..." is added to a query that CMap
# does to display correspondences.
sqlite3 ${CMAP_ROOT}/db/${DATASOURCE}.db 'ANALYZE'
