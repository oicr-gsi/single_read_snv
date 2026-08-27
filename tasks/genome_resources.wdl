version 1.0

# Auto-generated genome resources file
# Do not edit manually - regenerate using: wdls make-genome-resources target=<target>

struct GenomeResources {
  File ref_dict
  File ref_fasta
  File ref_fasta_index
  File srsnv_training_interval_list
}

workflow GenomeResourcesWorkflow {
  output {
    Map[String, GenomeResources] resources = {
      "hg38": {
        "ref_dict": "/.mounts/labs/gsi/testdata/efficient_dv/input_data/Homo_sapiens_assembly38.dict",
        "ref_fasta": "/.mounts/labs/gsi/testdata/efficient_dv/input_data/Homo_sapiens_assembly38.fasta",
        "ref_fasta_index": "/.mounts/labs/gsi/testdata/efficient_dv/input_data/Homo_sapiens_assembly38.fasta.fai",
        "srsnv_training_interval_list": "/.mounts/labs/gsi/testdata/single_read_snv/input_data/wgs_calling_regions.without_encode_blacklist.hg38.chr1_22.interval_list"
}
    }
  }
}
