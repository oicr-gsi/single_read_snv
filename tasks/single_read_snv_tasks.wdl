version 1.0
# LICENSE
#   Copyright 2022 Ultima Genomics
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#


import "structs.wdl" as Structs
task PrepareFeatureMapForTraining {
  parameter_meta {
    jobMemory: {
      help: "Memory in GiB to allocate for the PrepareFeatureMapForTraining task",
      type: "Int",
      category: "runtime"
    }
    modules: {
      help: "Modules to use with the task",
      type: "String",
      category: "runtime"
    }
    timeout: {
      help: "Time allocated for running the task",
      type: "Int",
      category: "runtime"
    }
  }
  input {
    File featuremap
    File featuremap_index
    SingleReadSNVParams single_read_snv_params
    Int train_set_size
    String filter_json_key
    File read_filters_with_max_coverage
    String docker
    String modules = "apptainer/1.4.5"
    File monitoring_script
    Int jobMemory = 2
    Int timeout = 10
  }

  Float featuremap_size = size(featuremap, "GiB")
  Int disk_size = ceil(featuremap_size * 3 + 20)

  String base_file_name = basename(featuremap, ".vcf.gz")
  String filtered_parquet = base_file_name + ".filtered.parquet"

  command <<<
    set -xeuo pipefail
    bash ~{monitoring_script} | tee monitoring.log >&2 &
    # De-reference inputs
    MAP=$(readlink -f ~{featuremap})
    MAPDIR=${MAP%/*}

    COVER=$(readlink -f ~{read_filters_with_max_coverage})
    COVERDIR=${COVER%/*}

    # Convert featuremap to parquet
    apptainer exec \
      --bind ${PWD}:${PWD},${MAPDIR}:${MAPDIR},${COVERDIR}:${COVERDIR} \
      --userns \
      ~{docker} \
      featuremap_to_dataframe \
    --input ${MAP} \
    --output ~{filtered_parquet} \
    --drop-format GT AD X_TCM \
    --read-filter-json-key ~{filter_json_key} \
    --read-filters-json ${COVER} \
    --downsample-reads ~{train_set_size} \
    --downsample-seed ~{single_read_snv_params.random_seed} \
    --verbose
  >>>

  runtime {
    memory: "~{jobMemory} GB"
    modules: "~{modules}"
    timeout: "~{timeout}"
  }

  output {
    File filtered_featuremap_parquet = "~{filtered_parquet}"
    File monitoring_log = "monitoring.log"
  }
}

task TrainModel {
  parameter_meta {
    jobMemory: {
      help: "Memory in GB to allocate for the PrepareFeatureMapForTraining task",
      type: "Int",
      category: "runtime"
    }
    threads: {
      help: "Number of CPUs to allocate for the TrainModel task",
      type: "Int",
      category: "runtime"
    }
    timeout: {
      help: "Time allocated for running the task",
      type: "Int",
      category: "runtime"
    }
  }

  input {
    File raw_filtered_featuremap_parquet
    File random_sample_filtered_featuremap_parquet
    File stats_file
    Float mean_coverage
    File xgboost_params_file
    SingleReadSNVParams single_read_snv_params
    File training_interval_list
    Array[String] features
    String base_file_name
    String docker
    String modules = "apptainer/1.4.5"
    String pipeline_version
    Int preemptible_tries
    File monitoring_script
    Int jobMemory = 32
    Int timeout = 10
    Int threads = ceil(jobMemory / 2)
  }

  Float featuremap_size = size(raw_filtered_featuremap_parquet, "GiB") + size(random_sample_filtered_featuremap_parquet, "GiB")
  Int disk_size = ceil(featuremap_size*3 + size(training_interval_list, "GiB") + 20)

  command <<<
    set -xeuo pipefail
    bash ~{monitoring_script} | tee monitoring.log >&2 &

    # De-reference the input files
    RAWPARQ=$(readlink -f ~{raw_filtered_featuremap_parquet})
    RAWPARQDIR=${RAWPARQ%/*}

    FILTPARQ=$(readlink -f ~{random_sample_filtered_featuremap_parquet})
    FILTPARQDIR=${FILTPARQ=%/*}
    
    STATF=$(readlink -f ~{stats_file})
    STATFDIR=${STATF%/*}

    XBOOSTPF=$(readlink -f ~{xgboost_params_file})
    XBOOSTPFDIR=${XBOOSTPF%/*}

    TINT=$(readlink -f ~{training_interval_list})
    TINTDIR=${TINT%/*}
  
    PARENT_DIR="$(realpath "$PWD/..")"
     
    apptainer exec \
      --bind ${PWD}:${PWD} \
      --bind ${PARENT_DIR}:${PARENT_DIR} \
      --bind ${RAWPARQDIR}:${RAWPARQDIR} \
      --bind ${FILTPARQDIR}:${FILTPARQDIR} \
      --bind ${STATFDIR}:${STATFDIR} \
      --bind ${XBOOSTPFDIR}:${XBOOSTPFDIR} \
      --bind ${TINTDIR}:${TINTDIR} \
      --userns \
      ~{docker} \
      srsnv_training \
    --positive $FILTPARQ \
    --negative $RAWPARQ \
    --stats-file $STATF \
    --mean-coverage ~{mean_coverage} \
    --training-regions $TINT \
    --k-folds ~{single_read_snv_params.num_CV_folds} \
    --model-params $XBOOSTPF \
    --output $PWD \
    --basename ~{base_file_name} \
    --features ~{sep=":" features} \
    --random-seed ~{single_read_snv_params.random_seed} \
    --metadata docker_image="~{docker}" \
    --metadata pipeline_version="~{pipeline_version}" \
    --verbose

    ls -ltr
    
  >>>

  runtime {
    cpu: "~{threads}"
    modules: "~{modules}"
    timeout: "~{timeout}"
    memory: "~{jobMemory} GB"
  }

  output {
    File featuremap_df = "~{base_file_name}.featuremap_df.parquet"
    File srsnv_metadata_json = "~{base_file_name}.srsnv_metadata.json"
    Array[File] model_files = glob("~{base_file_name}.model_fold_*.json")
    File monitoring_log = "monitoring.log"
  }
}

task CreateFeatureMap {
  parameter_meta {
    jobMemory: {
      help: "Memory in GiB to allocate for the CreateFeatureMap task",
      type: "Int",
      category: "runtime"
    }
    modules: {
      help: "Environment modules to use with the task",
      type: "Str",
      category: "runtime"
    }
    timeout: {
      help: "Time allocated for running the task",
      type: "Int",
      category: "runtime"
    }
  }
  input {
    Array[File] input_cram_bam_list
    Array[File] input_cram_bam_index_list
    References references
    String base_file_name
    String total_aligned_bases
    Float? mean_coverage
    Int random_sample_size
    File? random_sample_trinuc_freq_
    FeatureMapParams featuremap_params
    FeaturemapAnnotationFiles annotation_files
    Array[SingleReadSNVModel]? model_files         # Model SingleReadSNVModel structs (-M flag)
    String docker
    File monitoring_script
    Int jobMemory
    Int timeout = 186
    Int cpus = 2
    String modules = "apptainer/1.4.5 bcftools/1.9 jq/1.8.1"
    Float? max_coverage_factor
  }

  String out_vcf = "~{base_file_name}.raw.featuremap.vcf.gz"
  String out_vcf_random_sample = "~{base_file_name}.random_sample.featuremap.vcf.gz"
  String out_random_sample_trinuc_freq = "~{base_file_name}.random_sample.trinuc_freq.csv"
  String out_model_filters_status_funnel = "~{base_file_name}.model_filters_status.funnel.json"

  # Calculate coverage threshold (factor times mean coverage) only if read_filters are provided
  Int coverage_threshold = if defined(featuremap_params.read_filters) then ceil(select_first([mean_coverage, 1]) * select_first([max_coverage_factor, 20])) else 20

  # Extract model files from SingleReadSNVModel structs (applicable for only 2 models!)
  # As WDL 1.0 workaround, use Array[File] with 0-or-1 elements for model_metadata optional File (no None literal)
  Array[SingleReadSNVModel] model_files_ = select_first([model_files, []])
  Array[File] model_0_metadata_files = if length(model_files_) > 0 then [model_files_[0].model_metadata] else []
  Array[File] model_0_fold_files = if length(model_files_) > 0 then model_files_[0].model_fold_files else []
  Array[File] model_1_metadata_files = if length(model_files_) > 1 then [model_files_[1].model_metadata] else []
  Array[File] model_1_fold_files = if length(model_files_) > 1 then model_files_[1].model_fold_files else []

  command <<<
    lscpu
    #set -xeuo pipefail
    bash ~{monitoring_script} | tee monitoring.log >&2 &

    ##################### Generate random sample #####################
    TOTAL_ALIGNED_BASES="~{total_aligned_bases}"
    GENERATE_RANDOM_SAMPLE="~{select_first([featuremap_params.generate_random_sample, true])}"
    
    # If generate_random_sample is true, validate TOTAL_ALIGNED_BASES
    if [ "$GENERATE_RANDOM_SAMPLE" = "true" ]; then
      if [ "$TOTAL_ALIGNED_BASES" = "0" ] || [ "$TOTAL_ALIGNED_BASES" = "" ]; then
        echo "Error: generate_random_sample is set to true, but TOTAL_ALIGNED_BASES is zero or empty (value: '$TOTAL_ALIGNED_BASES')" >&2
        echo "Cannot generate random sample without valid total aligned bases count." >&2
        exit 1
      fi
      
      echo "Total aligned bases: $TOTAL_ALIGNED_BASES"
      DOWNSAMPLING_RATE=$(awk -v num=~{random_sample_size} -v den="$TOTAL_ALIGNED_BASES" 'BEGIN{printf "%.12f", num/den}')
      echo "Downsampling rate: $DOWNSAMPLING_RATE"

      # Build random sample args, this needs to be de-referenced
      RANDOM_SAMPLE_TRINUC_ARGS=""
      if [ -n "~{default='' random_sample_trinuc_freq_}" ]; then
        REAL_FREQ=$(readlink -f ~{random_sample_trinuc_freq_})
        RANDOM_SAMPLE_TRINUC_ARGS=",${REAL_FREQ},~{out_random_sample_trinuc_freq}"
      fi

    
      # Build random sample flag (in bash to avoid WDL parsing issues with bash variables)
      RANDOM_SAMPLE_FLAG="-f ~{out_vcf_random_sample},${DOWNSAMPLING_RATE}${RANDOM_SAMPLE_TRINUC_ARGS}"
    else
      DOWNSAMPLING_RATE="0.0"
      RANDOM_SAMPLE_FLAG=""
    fi

    ##################### Set up model directories #####################
    ## NOTE: Only applicable for 2 models!
    MODEL_FLAG=""
    if [ -n "~{sep='' model_0_metadata_files}" ]; then
      mkdir -p "model_0"
      cp ~{sep='' model_0_metadata_files} "model_0/"
      cp ~{sep=" " model_0_fold_files} "model_0/"
      MODEL_FLAG="-M model_0/$(basename ~{sep='' model_0_metadata_files})"
    fi
    if [ -n "~{sep='' model_1_metadata_files}" ]; then
      mkdir -p "model_1"
      cp ~{sep='' model_1_metadata_files} "model_1/"
      cp ~{sep=" " model_1_fold_files} "model_1/"
      MODEL_FLAG="${MODEL_FLAG},model_1/$(basename ~{sep='' model_1_metadata_files})"
    fi
    # If no model is provided, but a read_filters json file is provided, input it in -M flag
    if [ -z "$MODEL_FLAG" ] && [ -n "~{featuremap_params.read_filters}" ]; then
      # 1. Complete read_filters json file with maximal coverage threshold
      jq --argjson coverage_threshold ~{coverage_threshold} '(.filters_full_output[]? | select(.name == "coverage_le_max")) |= . + {value: $coverage_threshold} | (.filters_random_sample[]? | select(.name == "coverage_le_max")) |= . + {value: $coverage_threshold}' ~{featuremap_params.read_filters} > read_filters_with_max_coverage.json
      MODEL_FLAG="-M read_filters_with_max_coverage.json"
    fi

    ################### Resolve symbolic links ############
    declare -A seen_dirs
    BIND_ARGS="--bind ${PWD}:${PWD}"
    for f in ~{sep=' ' input_cram_bam_list}; do
        real=$(readlink -f "$f")
        crams_real+=("$real")
        dir=$(dirname "$real")
        seen_dirs["$dir"]=1
    done

    # This is a bit awkward, but we need to handle 3 annotation files differently
    real_dbsnp=$(readlink -f ~{annotation_files.dbsnp})
    dir_a=$(dirname "$real_dbsnp")
    seen_dirs["$dir_a"]=1

    real_gnomad=$(readlink -f ~{annotation_files.gnomad})
    dir_b=$(dirname "$real_gnomad")
    seen_dirs["$dir_b"]=1

    real_ug_hcr=$(readlink -f ~{annotation_files.ug_hcr})
    dir_c=$(dirname "$real_ug_hcr")
    seen_dirs["$dir_c"]=1

    # build bind arguments (we also use dirs for input crams retrieved earlier)
    BIND_ARGS=""
    MAPBED=""
    MAPBED_FILE=""

    for d in "${!seen_dirs[@]}"; do
        BIND_ARGS+=" --bind $d:$d"
    done

    # Resolve an optional BED file, if present
    if [ -f ~{featuremap_params.bed_file} ]; then
       MAPBED=$(readlink -f ~{featuremap_params.bed_file})
       MBDIR=${MAPBED%/*}
       MAPBED_FILE="-b $MAPBED"
       BIND_ARGS+=" --bind $MBDIR:$MBDIR"
    fi

    # Resolve optional random sample trinucleotide frequency file, if present
    if [ -f ~{random_sample_trinuc_freq_} ]; then
       REALFREQ=$(readlink -f ~{random_sample_trinuc_freq_})
       FREQDIR=$(dirname ${REALFREQ})
       BIND_ARGS+=" --bind $FREQDIR:$FREQDIR" 
    fi

    REF=$(readlink -f ~{references.ref_fasta})
    REFDIR=${REF%/*}

    ##################### Run snvfind #####################
    # Run snvfind with parameters
    export APPTAINER_TMPDIR=/tmp 
    apptainer exec \
      --bind ${PWD}:${PWD},${REFDIR}:${REFDIR} \
      $BIND_ARGS \
      --userns \
      ~{docker} \
      snvfind \
      $crams_real \
      $REF \
      -o ~{out_vcf} \
      ${RANDOM_SAMPLE_FLAG} \
      ${MODEL_FLAG} \
      -S ~{out_model_filters_status_funnel} \
      ~{true="-p" false="" defined(featuremap_params.padding_size)}~{default="" featuremap_params.padding_size} \
      ~{true="-L" false="" defined(featuremap_params.score_limit)}~{default="" featuremap_params.score_limit} \
      ~{true="-X" false="" defined(featuremap_params.max_score_to_emit)}~{default="" featuremap_params.max_score_to_emit} \
      ~{true="-N" false="" defined(featuremap_params.min_score_to_emit)}~{default="" featuremap_params.min_score_to_emit} \
      ~{true="-n" false="" select_first([featuremap_params.exclude_nan_scores, true])} \
      ~{true="-d" false="" select_first([featuremap_params.include_dup_reads, false])} \
      ~{true="-k" false="" select_first([featuremap_params.keep_supplementary, false])} \
      ~{true="-Q" false="" defined(featuremap_params.surrounding_quality_size)}~{default="" featuremap_params.surrounding_quality_size} \
      ~{true="-r" false="" defined(featuremap_params.reference_context_size)}~{default="" featuremap_params.reference_context_size} \
      ~{true="-m" false="" defined(featuremap_params.min_mapq)}~{default="" featuremap_params.min_mapq} \
      ~{true="-c" false="" defined(featuremap_params.cram_tags_to_copy)} ~{default="" sep="," featuremap_params.cram_tags_to_copy} \
      ~{true="-C" false="" defined(featuremap_params.attributes_prefix)} ~{default="" featuremap_params.attributes_prefix} \
      $MAPBED_FILE \
      ~{true="-F" false="" select_first([featuremap_params.somatic_filter_mode, false])} \
      ~{true="-w" false="" defined(featuremap_params.pileup_window_width)} ~{default="" featuremap_params.pileup_window_width} \
      -a ${real_dbsnp},ID \
      -a ${real_gnomad},AF,gnomAD_AF \
      -a ${real_ug_hcr},UG_HCR
    
    # Re-pack the vcf as it may be an issue with how docker gzips it
    gunzip -c ~{out_vcf} | bgzip -c > temp.vcf.gz && mv temp.vcf.gz ~{out_vcf}
    bcftools index -f -t ~{out_vcf}
    if [ "$GENERATE_RANDOM_SAMPLE" = "true" ]; then
      # index the random sample vcf
      gunzip -c ~{out_vcf_random_sample} | bgzip -c > temp_random.vcf.gz && mv temp_random.vcf.gz ~{out_vcf_random_sample}
      bcftools index -f -t ~{out_vcf_random_sample}
    fi
    
    printf '%s\n' "${DOWNSAMPLING_RATE}" > downsampling_rate.txt

    ls -ltr
  >>>

  runtime {
    memory: "~{jobMemory} GB"
    timeout: "~{timeout}"
    modules: "~{modules}"
    continueOnReturnCode: [0,134]
  }

  output {
    File featuremap = "~{out_vcf}"
    File featuremap_index = "~{out_vcf}.tbi"
    File? featuremap_random_sample = "~{out_vcf_random_sample}"
    File? featuremap_random_sample_index = "~{out_vcf_random_sample}.tbi"
    File? random_sample_trinuc_freq = "~{out_random_sample_trinuc_freq}"
    Float downsampling_rate = read_float("downsampling_rate.txt")
    File model_filters_status_funnel = "~{out_model_filters_status_funnel}"
    File? read_filters_with_max_coverage = "read_filters_with_max_coverage.json"
    File monitoring_log = "monitoring.log"
  }
}

task Inference {
  input {
    String base_file_name
    Array[File] model_files
    File srsnv_metadata_json
    File featuremap
    File monitoring_script
    String docker
    String modules = "bcftools/1.9 apptainer/1.4.5"
    Int threads = 4
    Int jobMemory = 8
  }

  Float featuremap_size = size(featuremap, "GiB")
  String out_vcf = "~{base_file_name}.featuremap.vcf.gz"

  command <<<
      lscpu
      set -xeuo pipefail
      bash ~{monitoring_script} | tee monitoring.log >&2 &

      # De-reference inputs
      FMAP=$(readlink -f ~{featuremap})
      FMAPDIR=${FMAP%/*}
 
      # prepare model files directory
      mkdir -p model_files
      cp ~{sep=" " model_files} model_files/
      cp ~{srsnv_metadata_json} model_files/srsnv_metadata.json

      # Run inference with snvqual
      export APPTAINER_TMPDIR=/tmp
      apptainer exec \
      --bind ${PWD}:${PWD} \
      --bind ${FMAPDIR}:${FMAPDIR} \
      --userns \
      ~{docker} \
      snvqual \
        $FMAP \
        "~{out_vcf}" \
        model_files/srsnv_metadata.json \
        -v

      bcftools index -t "~{out_vcf}"

      ls -ltr
   >>>

  runtime {
    cpu: "~{threads}"
    modules: "~{modules}"
    memory: "~{jobMemory} GB"
  }

  output {
    File featuremap_out = "~{out_vcf}"
    File featuremap_out_index = "~{out_vcf}.tbi"
    File monitoring_log = "monitoring.log"
  }
}

task CreateReport {
  input {
    File   featuremap_df
    File   srsnv_metadata_json
    Array[File] model_files
    String basename
    String docker
    Int    preemptible_tries
    File   monitoring_script
    String modules = "apptainer/1.4.5"
    Int    jobMemory = 32
    Int    threads      = 16
  }

  Float fm_size = size(featuremap_df, "GiB")
  Int   disk_size = ceil(fm_size + 10)

  command <<<
    set -euox pipefail
    bash ~{monitoring_script} | tee monitoring.log >&2 &

    # De-reference inputs
    FMAP=$(readlink -f ~{featuremap_df})
    FMAPDIR=${FMAP%/*}

    # Copy metadata and model files to PWD (Cromwell and Omics path support)
    cp ~{sep=" " model_files} .
    cp ~{srsnv_metadata_json} srsnv_metadata.json
    export APPTAINER_TMPDIR=/tmp
    apptainer exec \
      --bind ${PWD}:${PWD} \
      --bind ${FMAPDIR}:${FMAPDIR} \
      --userns \
      ~{docker} \
    srsnv_report \
      --featuremap-df $FMAP \
      --srsnv-metadata srsnv_metadata.json \
      --report-path . \
      --basename ~{basename} \
      --verbose

    ls -ltr
  >>>


  runtime {
    cpu: "~{threads}"
    memory: "~{jobMemory} GB"
    modules: "~{modules}"
  }

  output {
    File application_qc_h5 = "~{basename}.single_read_snv.applicationQC.h5"
    File report_html       = "~{basename}.report.html"
    File monitoring_log    = "monitoring.log"
  }
}
