version 1.0

# OICR NOTICE: Multiple tasks were modified to use docker containers via Apptainer (former Singularity) developed by Berkeley National Lab
# This particular file was to modified so that configuration tells us where pre-loaded docker images reside
# the paths are and should be absolute, no symlinks here

struct GlobalVariables {
  String ubuntu_docker
  String monitoring_script
  String ugbio_core_docker
  String ugbio_featuremap_docker
  String ugbio_srsnv_docker
  String featuremap_docker
}
workflow Globals {
  input {
  GlobalVariables glob = {
        "ubuntu_docker": "/.mounts/labs/gsi/testdata/single_read_snv/docker_images/ubuntu.sif",
        "monitoring_script": "/.mounts/labs/gsi/testdata/single_read_snv/input_data/monitor_1.0.sh",
        "ugbio_core_docker": "/.mounts/labs/gsi/testdata/single_read_snv/docker_images/ugbio_core.sif",
        "ugbio_featuremap_docker": "/.mounts/labs/gsi/testdata/single_read_snv/docker_images/ugbio_featuremap_docker.sif",
        "ugbio_srsnv_docker": "/.mounts/labs/gsi/testdata/single_read_snv/docker_images/ugbio_srsnv_docker.sif",
        "featuremap_docker": "/.mounts/labs/gsi/testdata/single_read_snv/docker_images/featuremap_docker.sif"
  }
}

  output {
    GlobalVariables global_dockers = glob
  }
}
